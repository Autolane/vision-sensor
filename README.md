# Vision Sensor Web App

A simple web application with authentication for streaming USB camera feed and capturing images on Raspberry Pi Zero 2W.

## Features

- User authentication (login/logout)
- Live camera streaming in browser
- Capture and download images directly to your computer
- Responsive design for mobile and desktop
- Optimized for Raspberry Pi Zero 2W

## Requirements

- Raspberry Pi Zero 2W
- USB Camera
- Python 3.11+
- Poetry (for dependency management)

## Quick Installation (Recommended)

For automated installation with system configuration, use the install script:

```bash
cd vision-sensor
sudo ./scripts/install.sh
```

The install script will:
- Prompt for hostname configuration
- Configure and activate 4G LTE modem (if available)
- Install all required system dependencies
- Install Poetry and Python packages
- Create a dedicated system user
- Configure the app to run automatically at startup
- Set up systemd service

After installation, the app will be available at `http://[YOUR_PI_IP]:5000`

## Manual Installation

If you prefer manual installation or development setup:

1. Install system dependencies:
```bash
sudo apt-get update
sudo apt-get install python3-pip python3-opencv
```

2. Install Poetry:
```bash
curl -sSL https://install.python-poetry.org | python3 -
```

Add Poetry to your PATH (add to ~/.bashrc or ~/.zshrc):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

3. Install Python dependencies using Poetry:
```bash
poetry install
```

This will automatically create a virtual environment and install all required packages.

## Configuration

The application uses environment variables for configuration. All settings are stored in the `.envrc` file in plain `KEY=value` format (compatible with both python-dotenv and systemd).

### Initial Setup

1. Copy the example environment file:
```bash
cp .envrc.example .envrc
```

2. Edit `.envrc` and customize the settings:
```bash
nano .envrc
```

### Important Configuration Settings

**Security Settings (CHANGE THESE!):**
- `FLASK_SECRET_KEY`: Secret key for Flask sessions (generate a random one)
- `DEFAULT_USERNAME`: Admin username for login
- `DEFAULT_PASSWORD`: Admin password for login

Generate a secure secret key:
```bash
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

**Server Settings:**
- `HOST`: Server host (default: 0.0.0.0 for network access)
- `PORT`: Server port (default: 5000)
- `FLASK_DEBUG`: Debug mode (True/False)

**Camera Settings:**
- `CAMERA_INDEX`: Camera device index (0 for first camera)
- `CAMERA_WIDTH`: Video width in pixels (default: 640)
- `CAMERA_HEIGHT`: Video height in pixels (default: 480)
- `CAMERA_FPS`: Frames per second (default: 15)
- `JPEG_QUALITY`: JPEG compression quality 1-100 (default: 80)

### Loading Environment Variables

The application automatically loads environment variables from `.envrc` using python-dotenv. No manual sourcing is required.

## Running the Application

1. Make sure your USB camera is connected

2. Run the application using Poetry:
```bash
poetry run python app.py
```

Or activate the Poetry shell and run directly:
```bash
poetry shell
python app.py
```

4. Access the web app:
   - From the same device: http://localhost:5000
   - From another device on the same network: http://[RASPBERRY_PI_IP]:5000

5. Login with your configured credentials (default: admin/admin123)

## Usage

1. After logging in, you'll see the live camera stream
2. Click "Capture Image" to capture and download a snapshot
3. Images are automatically downloaded to your browser's default download location with timestamps (e.g., `vision_sensor_20250113_143025.jpg`)

## Troubleshooting

### Camera not detected
- Check if the camera is properly connected
- Try different USB ports
- Verify camera with: `ls /dev/video*`
- Test camera: `v4l2-ctl --list-devices`

### Performance issues
The app is configured for optimal performance on Pi Zero 2W:
- Resolution: 640x480
- FPS: 15
- JPEG quality: 80%

You can adjust these settings in the `.envrc` file:
- `CAMERA_WIDTH` and `CAMERA_HEIGHT` for resolution
- `CAMERA_FPS` for frame rate
- `JPEG_QUALITY` for compression quality

### Access from other devices
- Make sure your Pi and other devices are on the same network
- Check firewall settings if needed
- Find your Pi's IP address: `hostname -I`

## Running on Boot

**Note:** If you used the automated install script, this is already configured! The sections below are for manual setup only.

To manually configure the app to run automatically on boot, create a systemd service:

1. Create service file:
```bash
sudo nano /etc/systemd/system/vision-sensor.service
```

2. Add the following content (adjust paths and user as needed):
```ini
[Unit]
Description=Vision Sensor Web App
After=network.target

[Service]
User=chadagate
WorkingDirectory=/home/chadagate/vision-sensor
EnvironmentFile=/home/chadagate/vision-sensor/.envrc
ExecStart=/home/chadagate/.local/bin/poetry run python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Note: Make sure the `EnvironmentFile` path points to your `.envrc` file and adjust the user to match your system.

3. Enable and start the service:
```bash
sudo systemctl enable vision-sensor
sudo systemctl start vision-sensor
```

4. Check service status:
```bash
sudo systemctl status vision-sensor
```

View logs:
```bash
sudo journalctl -u vision-sensor -f
```

## Security Notes

- **IMPORTANT**: Change default credentials in `.envrc` before using in production
- Generate a strong `FLASK_SECRET_KEY` using the provided command
- Never commit `.envrc` to version control (it's in .gitignore by default)
- Use HTTPS for secure connections (consider using nginx as reverse proxy)
- Keep the app behind a firewall if exposing to the internet
- Regularly update dependencies with `poetry update`
- Set `FLASK_DEBUG=False` in production environments

## License

Free to use and modify for personal and commercial projects.
