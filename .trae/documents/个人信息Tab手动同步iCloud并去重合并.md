## 现状确认
- 个人信息页面入口在 [ContentView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/ContentView.swift#L4-L27) 的 TabView（PersonalInfoView）。
- 个人信息表单页在 [PersonalInfoView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/PersonalInfo/PersonalInfoView.swift#L4-L122)，当前仅做本地 Core Data 读写。
- 持久化使用 `NSPersistentCloudKitContainer`（[Persistence.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Persistence.swift#L44-L91)），并开启 history + remote change 通知；模型中所有实体 `syncable="YES"`（[contents](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/MuscleMetric.xcdatamodeld/MuscleMetric.xcdatamodel/contents#L1-L59)）。

## 目标
- 在“个人信息”Tab 增加一个“手动同步 iCloud 数据”入口。
- 点击后：
  1) 尽量拉取最新云端变更到本机（依赖 CoreData+CloudKit 自动 import/export 机制）。
  2) 若出现两端数据不一致导致的重复/冲突（常见表现：同一 UUID 的对象出现多份），在本地执行去重合并。
  3) 合并后的结果保存到本地，并通过 CloudKit 自动导出回云端，从而“更新本地与 iCloud 上的数据”。

## 方案设计
### 1) 新增同步管理器（核心逻辑）
- 新增一个独立的同步组件（例如 `CloudManualSyncService`/`DataReconciler`），对外提供：
  - `manualSync(container:) async throws -> SyncReport`
- `manualSync` 的流程：
  1. 先在主线程保存一次 `viewContext`（把用户本地修改推入 store，触发 export）。
  2. 监听 `NSPersistentCloudKitContainer.eventChangedNotification`（若可用）来观察 import/export 事件；在 UI 上显示“正在同步”。
  3. 在 `container.performBackgroundTask` 的后台 context 里执行“去重合并”。
  4. 保存后台 context；返回合并统计（合并/删除数量、涉及实体数）。
  5. 回到主线程 `viewContext.refreshAllObjects()` 并再次保存（如需要）以保证 UI 与 store 一致。

### 2) 去重合并策略（稳定且可解释）
- 统一以每个实体的 `id: UUID` 作为主键（模型里所有实体都有 `id`，见 [contents](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/MuscleMetric.xcdatamodeld/MuscleMetric.xcdatamodel/contents#L3-L58)）。
- 处理步骤（对每个实体分别执行）：
  1. 先修复缺失主键：`id == nil` 的对象补一个新的 UUID，避免后续无法归并。
  2. 按 `id` 分组：同一 `id` 多个对象视为“重复项”。
  3. 选定 canonical（保留者）：默认选择“字段更完整/非默认值更多”的那份。
  4. 合并属性：把 duplicate 中“更有信息量”的字段补到 canonical 上（例如字符串非空、数值非 0）。
  5. 合并关系：
     - to-one：canonical 为空则用 duplicate 的；若两边都不为空且冲突，保持 canonical（避免误合并）。
     - to-many：取并集，并确保 inverse 关系正确（例如 `Entry.record` / `Record.entries`）。
  6. 删除 duplicate 对象。
- 对不同实体的“默认值判断”会做小差异化：
  - `UserProfile`: `age>0/height>0/weight>0` 与字符串非空优先。
  - `TrainingRecord/DietRecord`: 日期/标题/能量字段按“非空优先”；entries 取并集。
  - `TrainingEntry/DietEntry`: action/weight/food/record 等关键关系优先补全；`orderIndex` 优先保留已有非默认值。
  - `TrainingTag/DietTag`: 名称/分类非空优先，宏量营养等数值优先保留非 0。

### 3) UI 集成到个人信息页
- 修改 [PersonalInfoView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/PersonalInfo/PersonalInfoView.swift#L4-L122)：
  - 新增一个 Section：显示 iCloud 状态 + “手动同步”按钮。
  - 点击后用 `Task { await ... }` 调用同步管理器；期间禁用按钮并显示 ProgressView。
  - 同步完成/失败用 alert 提示（展示 SyncReport 里的合并统计）。

### 4) 可选增强（更可靠的“手动同步”体验）
- iCloud 可用性检查：使用 `CKContainer.default().accountStatus`（需要 `import CloudKit`）或 `FileManager.default.ubiquityIdentityToken` 提前提示用户“未登录 iCloud/未开启 iCloud Drive”。
- 同步事件可视化：如果能拿到 CloudKit import/export 事件，在 UI 上显示最近一次同步时间与状态。

## 需要修改/新增的文件
- 修改：
  - [PersonalInfoView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/PersonalInfo/PersonalInfoView.swift)
- 新增（建议放到 `MuscleMetric/Sync/` 或 `MuscleMetric/Services/`）：
  - `CloudManualSyncService.swift`（手动同步入口 + 事件监听）
  - `CoreDataDeduplicator.swift`（按实体执行去重合并，输出统计）
- 可选修改：
  - [Persistence.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Persistence.swift)（补充一个可复用的 `performBackgroundTask` async 包装/统一注入 container）

## 验证方式
- 单元测试（in-memory CoreData）：
  - 构造重复对象（同一 `id` 两份）+ 冲突字段（一个有值一个默认值）。
  - 运行 dedupe 后断言：
    - 只剩 1 份对象；
    - canonical 字段被正确补全；
    - 关系（entries/record、tag/entry）仍一致。
- 真机手测：
  - 两台设备分别写入数据、等待同步后点击“手动同步”，观察是否能合并重复并最终两端一致。

## 风险与边界说明
- `NSPersistentCloudKitContainer` 没有“强制立刻从云端拉取”的公开 API；本方案的“手动同步”会尽可能：先保存触发导出 + 等待系统 import/export 事件 + 本地去重合并后再保存导出。
- 本方案不会尝试按“语义相同但 UUID 不同”的规则强行合并（例如两个不同 id 但标题/时间相同），避免误合并导致数据丢失；仅以同一 `id` 的多份对象为“重复”的确定信号。