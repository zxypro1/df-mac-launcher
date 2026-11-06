#!/bin/zsh
set -e

SCRIPT_DIR="${0:A:h}"
OUT_DIR="${1:-${SCRIPT_DIR:h}}"
STAGE_ROOT="/tmp/DF_Launcher_DMG_Stage"
OUT_DMG="$OUT_DIR/Dwarf_Fortress_Launcher_Mac.dmg"

echo "================================================================"
echo "  Building Dwarf Fortress Mac Launcher (.app & .dmg)"
echo "================================================================"

"$SCRIPT_DIR/build_app.sh" "$OUT_DIR"

rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE_ROOT"

cp -R "$OUT_DIR/Dwarf Fortress Launcher.app" "$STAGE_ROOT/"
ln -s /Applications "$STAGE_ROOT/Applications"

cat << 'EOF' > "$STAGE_ROOT/Fix_Gatekeeper_First_Launch.command"
#!/bin/zsh
DIR="${0:A:h}"
echo "Clearing macOS Gatekeeper quarantine attributes..."
xattr -cr "/Applications/Dwarf Fortress Launcher.app" 2>/dev/null || true
xattr -cr "$DIR/Dwarf Fortress Launcher.app" 2>/dev/null || true
echo "✅ Done! You can now open 'Dwarf Fortress Launcher' from /Applications."
echo "✅ 已清除 Gatekeeper 隔离标记，现在可直接从「应用程序」打开启动器。"
EOF
chmod +x "$STAGE_ROOT/Fix_Gatekeeper_First_Launch.command"

rm -f "$OUT_DMG"
hdiutil create -volname "Dwarf Fortress Launcher" -srcfolder "$STAGE_ROOT" -ov -format ULFO "$OUT_DMG"
rm -rf "$STAGE_ROOT"

echo ""
echo "✅ Built DMG: $OUT_DMG"
ls -lh "$OUT_DMG"
