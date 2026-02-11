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

## � 数据找回与排查（卸载重装后数据为空）

CloudKit 的数据隔离维度是：**iPhone 登录的 Apple ID（iCloud 账号） + CloudKit Container（容器，隶属某个开发者 Team） + App 的 Bundle ID/签名环境**。因此出现“卸载重装后数据没了”，通常是以下原因之一：

- **数据从未成功上传到 CloudKit**：卸载 App 会删除本地 Core Data 数据库，如果此前同步还没完成或根本没启用 iCloud/CloudKit capability，那么云端不会有数据可拉回。
- **CloudKit 容器/Team 变了**：切换开发者账号（Team）后，哪怕 Bundle ID 不变，CloudKit 容器也可能指向另一个 Team 下的同名容器（或新的默认容器），新安装的 App 会看到“空数据库”。
- **Development/Production 环境不一致**：Xcode 直连运行通常使用 Development 环境；TestFlight/App Store 使用 Production 环境。两者数据互不相通。
- **同步还在进行**：首次安装需要时间从云端下载；确保前台运行、Wi‑Fi、并开启 iCloud。

建议按顺序排查：

1. 在 iPhone 设置里确认已登录 iCloud，且 iCloud 可用（网络、空间、未禁用）。
2. 在 Xcode 的 Signing & Capabilities 中启用 iCloud，并勾选 CloudKit，确认 CloudKit Container 与预期一致。
3. 在 CloudKit Dashboard 中检查容器与环境（Development/Production）：
   - 选择正确的 Container
   - 切换到正确的 Environment
   - 查看是否存在记录（若完全没有记录，基本可判定旧数据未上云）
4. 如果你有“删除 App 之前”的整机备份（iCloud/iTunes），恢复该备份可能找回仅存在本地的数据；否则卸载后通常无法恢复本地数据库。

运行工程时，控制台会输出最小化诊断信息（如 bundleIdentifier、推导出的 CloudKit containerIdentifier、Core Data store 路径），用于快速判断当前构建是否真的在走 CloudKit 同步。

## �🛠 技术栈

- **语言**: Swift 5+
- **UI 框架**: SwiftUI
- **数据持久化**: Core Data
- **云同步**: CloudKit (NSPersistentCloudKitContainer)
- **最低支持版本**: iOS 16.0+

## 🚀 如何运行

1. 克隆项目到本地：
   ```bash
   git clone https://github.com/WIZOooo/muscle-metric.git
   ```
2. 使用 Xcode 打开 `MuscleMetric.xcodeproj`。
3. 配置 Signing & Capabilities：
   - 选择你的开发团队 (Team)。
   - 确保 iCloud 权限已开启，并配置好 CloudKit Container。
4. 在模拟器或真机上运行应用。
