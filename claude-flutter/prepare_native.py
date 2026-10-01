"""Create a clean Flutter shell and wire this source into both native platforms."""
import argparse
import pathlib
import re
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("destination")
args = parser.parse_args()
source = pathlib.Path(__file__).resolve().parent
dest = pathlib.Path(args.destination).resolve()
if dest.exists():
    raise SystemExit("Use an empty output path; existing projects are not overwritten.")
subprocess.run(["flutter", "create", "--org", "mn.acs", "--project-name", "ghost_detector",
                "--platforms", "android,ios", str(dest)], check=True)
for name in ("lib", "assets", "test"):
    if (source / name).exists():
        shutil.copytree(source / name, dest / name, dirs_exist_ok=True)
(dest / "test/widget_test.dart").unlink(missing_ok=True)
shutil.copy2(source / "pubspec.yaml", dest / "pubspec.yaml")
shutil.copy2(source / "platform/ios/AppDelegate.swift", dest / "ios/Runner/AppDelegate.swift")
kt = dest / "android/app/src/main/kotlin/mn/acs/ghost_detector/MainActivity.kt"
kt.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source / "platform/android/MainActivity.kt", kt)
manifest = dest / "android/app/src/main/AndroidManifest.xml"
text = manifest.read_text()
permissions = '\n<uses-permission android:name="android.permission.CAMERA"/>\n<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n<uses-feature android:name="android.hardware.camera" android:required="false"/>\n<uses-feature android:name="android.hardware.sensor.compass" android:required="false"/>\n'
text = re.sub(r"(<manifest\b[^>]*>)", lambda m: m[1] + permissions, text, count=1)
manifest.write_text(text)
gradle = dest / "android/app/build.gradle.kts"
if gradle.exists():
    text = gradle.read_text().replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
    gradle.write_text(text)
else:
    gradle = dest / "android/app/build.gradle"
    gradle.write_text(gradle.read_text().replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23"))
plist = dest / "ios/Runner/Info.plist"
text = plist.read_text()
for key, description in {
    "NSCameraUsageDescription": "Record environmental images and video.",
    "NSMicrophoneUsageDescription": "Record environmental audio.",
    "NSPhotoLibraryAddUsageDescription": "Save captured images and video.",
    "NSMotionUsageDescription": "Measure motion and the magnetic field using device sensors.",
}.items():
    if f"<key>{key}</key>" not in text:
        text = re.sub(r"</dict>\s*</plist>\s*$", f"<key>{key}</key><string>{description}</string>\n</dict>\n</plist>", text)
plist.write_text(text)
project = dest / "ios/Runner.xcodeproj/project.pbxproj"
project.write_text(re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", project.read_text()))
(dest / "ios/Podfile").write_text('''platform :ios, '15.5'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', {'Debug' => :debug, 'Profile' => :release, 'Release' => :release}
def flutter_root
  generated = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  File.foreach(generated) do |line|
    matches = line.match(/FLUTTER_ROOT\\=(.*)/)
    return matches[1].strip if matches
  end
  raise 'FLUTTER_ROOT not found'
end
require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup
target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'PERMISSION_CAMERA=1', 'PERMISSION_MICROPHONE=1']
    end
  end
end
''')
print(dest)
