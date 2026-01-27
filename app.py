from flask import Flask, render_template, Response, request, redirect, url_for, flash, jsonify, send_file
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
import cv2
import os
from datetime import datetime
import threading
from dotenv import load_dotenv
from io import BytesIO

# Load environment variables from .envrc
load_dotenv('.envrc')

app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'default-insecure-key-change-this')

# Configure Flask-Login
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Simple user class
class User(UserMixin):
    def __init__(self, id, username, password_hash):
        self.id = id
        self.username = username
        self.password_hash = password_hash

# Simple user database (in production, use a real database)
DEFAULT_USERNAME = os.getenv('DEFAULT_USERNAME', 'admin')
DEFAULT_PASSWORD = os.getenv('DEFAULT_PASSWORD', 'admin123')

users = {
    DEFAULT_USERNAME: User('1', DEFAULT_USERNAME, generate_password_hash(DEFAULT_PASSWORD))
}

@login_manager.user_loader
def load_user(user_id):
    for user in users.values():
        if user.id == user_id:
            return user
    return None

# Camera class for handling video stream
class VideoCamera:
    def __init__(self):
        self.camera = None
        self.lock = threading.Lock()
        self.initialize_camera()

    def initialize_camera(self):
        """Initialize the USB camera"""
        try:
            # Get camera settings from environment variables
            camera_index = int(os.getenv('CAMERA_INDEX', '0'))
            camera_width = int(os.getenv('CAMERA_WIDTH', '640'))
            camera_height = int(os.getenv('CAMERA_HEIGHT', '480'))
            camera_fps = int(os.getenv('CAMERA_FPS', '15'))

            # Try to open the configured camera
            self.camera = cv2.VideoCapture(camera_index)
            if not self.camera.isOpened():
                print(f"Warning: Could not open camera {camera_index}, trying camera {camera_index + 1}")
                self.camera = cv2.VideoCapture(camera_index + 1)

            if self.camera.isOpened():
                # Set camera properties for better performance on Pi Zero 2W
                self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, camera_width)
                self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, camera_height)
                self.camera.set(cv2.CAP_PROP_FPS, camera_fps)
                print(f"Camera initialized successfully: {camera_width}x{camera_height}@{camera_fps}fps")
            else:
                print("Error: Could not open camera")
        except Exception as e:
            print(f"Error initializing camera: {e}")
            self.camera = None

    def get_frame(self):
        """Get a single frame from the camera"""
        with self.lock:
            if self.camera is None or not self.camera.isOpened():
                self.initialize_camera()

            if self.camera is not None and self.camera.isOpened():
                success, frame = self.camera.read()
                if success:
                    return frame
        return None

    def get_jpeg_frame(self):
        """Get a JPEG encoded frame"""
        frame = self.get_frame()
        if frame is not None:
            jpeg_quality = int(os.getenv('JPEG_QUALITY', '80'))
            ret, jpeg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality])
            if ret:
                return jpeg.tobytes()
        return None

    def __del__(self):
        if self.camera is not None:
            self.camera.release()

# Global camera instance
camera = VideoCamera()

def generate_frames():
    """Generator function for video streaming"""
    while True:
        frame = camera.get_jpeg_frame()
        if frame is not None:
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
        else:
            # If no frame, wait a bit before trying again
            import time
            time.sleep(0.1)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')

        user = users.get(username)
        if user and check_password_hash(user.password_hash, password):
            login_user(user)
            return redirect(url_for('index'))
        else:
            flash('Invalid username or password')

    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def index():
    return render_template('index.html')

@app.route('/video_feed')
@login_required
def video_feed():
    """Video streaming route"""
    return Response(generate_frames(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/capture', methods=['GET'])
@login_required
def capture():
    """Capture and download an image"""
    try:
        # Get a frame from the camera
        frame = camera.get_frame()
        if frame is None:
            return jsonify({'success': False, 'error': 'Failed to capture image from camera'}), 500

        # Encode frame as JPEG
        jpeg_quality = int(os.getenv('JPEG_QUALITY', '80'))
        ret, jpeg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality])

        if not ret:
            return jsonify({'success': False, 'error': 'Failed to encode image'}), 500

        # Create a BytesIO object from the JPEG data
        img_io = BytesIO(jpeg.tobytes())
        img_io.seek(0)

        # Generate filename with timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'vision_sensor_{timestamp}.jpg'

        # Send file as download
        return send_file(
            img_io,
            mimetype='image/jpeg',
            as_attachment=True,
            download_name=filename
        )
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

if __name__ == '__main__':
    # Get configuration from environment variables
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', '5000'))
    debug = os.getenv('FLASK_DEBUG', 'False').lower() in ('true', '1', 'yes')

    # Run the Flask app
    # Use 0.0.0.0 to make it accessible from other devices on the network
    app.run(host=host, port=port, debug=debug, threaded=True)
