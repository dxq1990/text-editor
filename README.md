# Text Editor

macOS 上的轻量文本编辑器。界面是中文，适合打开、查看和做简单修改；更重的开发仍建议用专门的编辑器。

需要 macOS 14 或更高版本，以及 Xcode 命令行工具。

## 功能

- 多标签，记住上次打开的文件和未保存的内容
- 语法高亮和括号匹配：Markdown、JSON、HTML、XML、CSS、JavaScript、TypeScript、Python、SQL、Shell、YAML、C/C++、C#、Java
- 查找和替换，可跨标签
- 自动换行、行号、浅色和深色主题
- Markdown 预览
- 编码切换、最近打开、拖入文件

## 运行

```bash
bash scripts/run.sh
```

脚本会编译并打开 `dist/Text Editor.app`。

## 测试

先编译出 `EditorCore`，再运行检查脚本：

```bash
mkdir -p .build
swiftc -swift-version 5 -module-name EditorCore Sources/EditorCore/*.swift \
  -emit-module -emit-library -emit-module-path .build/EditorCore.swiftmodule \
  -o .build/libEditorCore.dylib
swiftc -swift-version 5 scripts/check.swift -I .build -L .build -lEditorCore -o .build/check
DYLD_LIBRARY_PATH=.build .build/check
```

## 许可

本项目以 [MIT 许可证](LICENSE) 发布。
