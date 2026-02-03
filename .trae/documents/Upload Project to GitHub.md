# 上传项目到 GitHub

我将帮助你把项目上传到 GitHub 仓库 `https://github.com/WIZOooo/muscle-metric.git`。

## 技术实现
1.  **创建 `.gitignore`**: 我注意到你的项目缺少 `.gitignore` 文件。我将创建一个包含标准 Swift 和 Xcode 忽略规则的文件（例如忽略 `xcuserdata`、`.DS_Store` 等），以保持仓库整洁。
2.  **配置远程仓库**: 将提供的 GitHub 链接添加为 `origin` 远程仓库。
3.  **暂存并提交**: 添加所有项目文件（包括新的 `.gitignore` 和当前未跟踪的文件）并创建提交。
4.  **推送代码**: 将代码推送到远程仓库的 `main` 分支。

## 步骤
1.  创建 `.gitignore` 文件。
2.  运行 `git remote add origin https://github.com/WIZOooo/muscle-metric.git`。
3.  运行 `git add .`。
4.  运行 `git commit -m "Initial commit"`。
5.  运行 `git push -u origin main`。
