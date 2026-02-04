我将为 MuscleMetric 生成一个中文 README.md 文件，并将其推送到远程仓库。

### 1. 生成 `README.md` 文件

我将在项目根目录下创建一个 `README.md` 文件，内容如下：

````markdown
# MuscleMetric

MuscleMetric 是一款专注于力量训练和饮食管理的 iOS 原生应用，旨在帮助用户高效记录训练重量与每日营养摄入。

## ✨ 核心功能

### 💪 力训记录 (Strength Training)
- **多级标签管理**：支持“健身门店 -> 器械/动作 -> 重量”的三级标签体系，快速记录训练内容。
- **上下文锁定**：选择门店后自动过滤相关动作，提升记录效率。
- **文本导出**：一键生成格式化的训练日志，便于分享。

### 🥗 饮食记录 (Diet Management)
- **营养追踪**：轻松记录每日热量、蛋白质、碳水化合物和脂肪摄入。
- **自定义食物库**：创建并管理常用的食物标签及其营养数据。
- **每日概要**：实时统计当日营养摄入总量。

### 🏷️ 标签管理 (Tag Management)
- 统一管理力训和饮食标签。
- 支持增删改查，灵活定制个性化的训练和饮食库。

### ☁️ iCloud 同步
- **本地优先 (Local-First)**：所有数据存储在本地 Core Data 中。
- **自动同步**：通过 CloudKit 自动在多台 iOS 设备间同步数据。
- **隐私安全**：无需注册账号，数据直接保存在用户的 iCloud 容器中。

## 🛠 技术栈

- **语言**: Swift 5+
- **UI 框架**: SwiftUI
- **数据持久化**: Core Data
- **云同步**: CloudKit (NSPersistentCloudKitContainer)
- **最低支持版本**: iOS 16.0+

## 🚀 如何运行

1. 克隆项目到本地：
   ```bash
   git clone https://github.com/WIZOooo/muscle-metric.git
````

1. 使用 Xcode 打开 `MuscleMetric.xcodeproj`。
2. 配置 Signing & Capabilities：

   * 选择你的开发团队 (Team)。

   * 确保 iCloud 权限已开启，并配置好 CloudKit Container。
3. 在模拟器或真机上运行应用。

```

### 2. Git 操作
文件生成后，我将执行以下 Git 命令：
1.  `git add README.md`：将文件添加到暂存区。
2.  `git commit -m "docs: add README.md"`：提交更改。
3.  `git push`：推送到远程仓库。
```

