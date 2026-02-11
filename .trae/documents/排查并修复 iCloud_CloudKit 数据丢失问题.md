## 结论先说（结合你补充的两个开发者账号）
- alb_zzz@163.com 与 lbc_zzz@sina.com 属于不同的 Apple Developer Team；CloudKit 容器是按 Team 隔离的，所以你用 lbc 的 Team 运行时看到“空”是正常的。
- 你切回 alb 并重装后仍然“空”，只剩两种最常见解释：
  1) 之前的数据其实从未成功上传到 CloudKit（一直只存在本机 App 沙盒里）；卸载后本地数据库被删，iCloud 自然拉不回来。
  2) 你现在虽然切回 alb，但实际仍没指向“当时的 CloudKit 容器/环境”（例如容器 ID 变了、Bundle ID 变了、或 Development/Production 环境不一致）。

## 我从仓库确认到的关键点
- 项目代码确实用 `NSPersistentCloudKitContainer`（[Persistence.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Persistence.swift#L44-L68)），但仓库里没有 entitlements，也没有在代码里显式绑定 CloudKit container identifier；这会导致“你以为在用 iCloud，但实际可能根本没启用 CloudKit，同步从没发生”。
- 工程当前写死的 `DEVELOPMENT_TEAM` 是 `G2ZUQ5958D`（[project.pbxproj](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric.xcodeproj/project.pbxproj#L393-L458)），这也意味着：切换账号/Team 时，工程配置很容易出现你以为切回了、但某些目标/配置没切干净的情况。

## 计划（确认后我会执行，并最终给你“能/不能找回”的明确判断）
1. 先把“是否真的有云端数据”判死刑/判生路：
   - 用 alb 对应 Team 的 CloudKit Dashboard 检查该 App 的容器（Container）里有没有记录，并核对环境（Development/Production）。
   - 如果容器里完全没有记录：基本可判定旧数据没上云，卸载后无法从 iCloud 找回；只有“恢复删除前的整机备份”或“另一台仍保留旧 App 数据的设备导出/同步”才可能找回。
2. 把工程的 iCloud/CloudKit 配置固化到仓库（避免再发生）：
   - 新增并提交 `*.entitlements`，显式启用 iCloud + CloudKit，并明确 CloudKit Container ID（用 alb Team 下创建的那个）。
3. 把代码显式绑定到该容器，并提供诊断输出：
   - 在 `Persistence.swift` 设置 `NSPersistentCloudKitContainerOptions(containerIdentifier: ...)`。
   - 启动时输出当前绑定的容器 ID、store 加载错误、以及是否启用了 CloudKit 选项，避免“静默只落本地”。
4. 真机恢复验证：
   - 在同一 Apple ID 登录的 iPhone 上运行（前台 + Wi‑Fi），验证是否能把云端记录拉回；若拉不回则根据日志定位（权限/环境/容器不一致）。

确认后我就开始按这个顺序做，并把每一步得到的证据（容器 ID/环境/日志）整理给你，这样你能非常确定旧数据到底还有没有找回可能。