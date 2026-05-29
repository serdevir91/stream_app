import os
from PIL import Image

def generate_icons():
    source_img_path = r"C:\Users\serde\.gemini\antigravity\brain\142104f4-c5cd-492e-927f-3818e7587871\stream_app_simple_logo_1780085260495.png"
    project_root = r"c:\Users\serde\OneDrive\Belgeler\Desktop\Code\stream_app"

    if not os.path.exists(source_img_path):
        print(f"Error: Source image not found at {source_img_path}")
        return

    img = Image.open(source_img_path)

    # 1. Windows Icon (.ico)
    windows_ico_path = os.path.join(project_root, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(windows_ico_path), exist_ok=True)
    img.save(windows_ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (256, 256)])
    print(f"Generated Windows icon: {windows_ico_path}")

    # 2. Android Icons
    android_res_dir = os.path.join(project_root, "android", "app", "src", "main", "res")
    android_sizes = {
        "mipmap-mdpi": (48, 48),
        "mipmap-hdpi": (72, 72),
        "mipmap-xhdpi": (96, 96),
        "mipmap-xxhdpi": (144, 144),
        "mipmap-xxxhdpi": (192, 192),
    }

    for folder, size in android_sizes.items():
        folder_path = os.path.join(android_res_dir, folder)
        os.makedirs(folder_path, exist_ok=True)
        out_path = os.path.join(folder_path, "ic_launcher.png")
        resized = img.resize(size, Image.Resampling.LANCZOS)
        resized.save(out_path, format="PNG")
        print(f"Generated Android icon: {out_path} ({size[0]}x{size[1]})")

    # 3. iOS Icons
    ios_icons_dir = os.path.join(project_root, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    ios_sizes = {
        "Icon-App-20x20@1x.png": (20, 20),
        "Icon-App-20x20@2x.png": (40, 40),
        "Icon-App-20x20@3x.png": (60, 60),
        "Icon-App-29x29@1x.png": (29, 29),
        "Icon-App-29x29@2x.png": (58, 58),
        "Icon-App-29x29@3x.png": (87, 87),
        "Icon-App-40x40@1x.png": (40, 40),
        "Icon-App-40x40@2x.png": (80, 80),
        "Icon-App-40x40@3x.png": (120, 120),
        "Icon-App-60x60@2x.png": (120, 120),
        "Icon-App-60x60@3x.png": (180, 180),
        "Icon-App-76x76@1x.png": (76, 76),
        "Icon-App-76x76@2x.png": (152, 152),
        "Icon-App-83.5x83.5@2x.png": (167, 167),
        "Icon-App-1024x1024@1x.png": (1024, 1024),
    }

    if os.path.exists(ios_icons_dir):
        for name, size in ios_sizes.items():
            out_path = os.path.join(ios_icons_dir, name)
            resized = img.resize(size, Image.Resampling.LANCZOS)
            resized.save(out_path, format="PNG")
            print(f"Generated iOS icon: {out_path} ({size[0]}x{size[1]})")
    else:
        print("iOS icons directory not found, skipping iOS icons.")

if __name__ == "__main__":
    generate_icons()
