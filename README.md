# Space Borders

A high-performance macOS window border tool written in Zig that highlights your active window with smooth, customizable borders.

## Requirements

- macOS 10.15 or later
- Zig 0.11.0 or later
- Accessibility permissions

## Building

```bash
# Clone the repository
git clone https://github.com/tornikegomareli/space-borders.git
cd space-borders

# Build with optimizations
zig build -Doptimize=ReleaseFast

# Or build for debugging
zig build
```

## Installation

1. Build the project
2. Grant Accessibility permissions when prompted

## Usage

```bash
# Run Space Borders
./zig-out/bin/space-borders
```

## Configuration

Configuration file location: `~/.config/space-borders/config.json`

### Default Configuration

```json
{
    "border_width": 2.0,
    "border_radius": 8.0,
    "active_color": {
        "r": 0.2,
        "g": 0.6,
        "b": 1.0,
        "a": 1.0
    },
    "animation_duration": 0.15,
    "enabled": true
}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `border_width` | float | Border thickness in pixels | 2.0 |
| `border_radius` | float | Corner radius in pixels | 8.0 |
| `active_color` | object | RGBA color for active window border | Blue (0.2, 0.6, 1.0, 1.0) |
| `animation_duration` | float | Animation duration in seconds | 0.15 |
| `enabled` | bool | Enable/disable borders | true |

## How it works

Space Borders uses several macOS technologies:

- **Core Graphics**
- **Accessibility API**
- **Core Video (CVDisplayLink)**
- **Objective-C Runtime**

The tool creates transparent overlay windows that track the active window's position and size, updating at 60fps.

## Permissions
Space Borders requires Accessibility permissions to:
- Monitor window positions and sizes
- Track the active/focused window
- Detect window state changes

You'll be prompted to grant these permissions on first run. To grant manually:
1. Open System Settings
2. Go to Privacy & Security → Accessibility
3. Add Terminal (or your terminal app) to the list
4. Enable the checkbox

## Performance

- **CPU Usage**: < 1% when idle, ~2-3% during window animations
- **Memory Usage**: ~5-10MB
- **Update Rate**: 60fps using CVDisplayLink
- **Latency**: < 16ms response time to window changes

## Troubleshooting

### Borders not appearing
- Ensure Accessibility permissions are granted
- Check if another window management tool is conflicting
- Try restarting the application

### Borders appear on wrong position
- This usually fixes itself after a window move

### Prerequisites
- Xcode Command Line Tools
- Zig 0.11.0 or later

### Build Commands
```bash
# Debug build
zig build

# Release build (recommended)
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Built with [Zig](https://ziglang.org/)
- Inspired by [SketchyBar](https://github.com/FelixKratz/SketchyBar)
