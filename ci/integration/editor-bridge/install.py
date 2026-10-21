"""Package the editor adapter without npm; use the existing VS Code CLI to install it."""

from pathlib import Path
import json
import shutil
import subprocess
import zipfile

source = Path(__file__).resolve().parent
repository = source.parents[2]
output = repository / "build" / "tools" / "editor-bridge.vsix"
output.parent.mkdir(parents=True, exist_ok=True)
manifest = json.loads((source / "package.json").read_text(encoding="utf-8"))
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
<Metadata><Identity Language="en-US" Id="local-actions-bridge" Version="{manifest['version']}" Publisher="template-tools"/>
<DisplayName>Local Actions Command Bridge</DisplayName><Description xml:space="preserve">Command-only local workflow access.</Description>
<Tags>local-actions</Tags><Categories>Other</Categories><GalleryFlags>Public</GalleryFlags>
<Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.93.0"/></Properties></Metadata>
<Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/>
<Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>'''
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("extension.vsixmanifest", xml)
    archive.writestr("[Content_Types].xml", '''<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="cjs" ContentType="application/javascript"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>''')
    for name in ("package.json", "extension.cjs"):
        archive.write(source / name, "extension/" + name)
code = shutil.which("code")
if not code:
    raise SystemExit("VS Code CLI 'code' must be on PATH")
subprocess.run([code, "--install-extension", str(output), "--force"], check=True)
