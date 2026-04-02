## 目标与入口
- 在“标签管理”页（[TagManagerView](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/TagManagement/TagManagerView.swift)）新增「导出/导入」能力。
- 力训标签（TrainingTag）与饮食标签（DietTag）分别导出为各自独立的 JSON 文件，并且导入时只接受对应格式。

## 数据范围与选择方式
- **导出前选择**：提供“全选/全不选/搜索/多选”的选择界面。
- **饮食标签**：扁平列表多选即可。
- **力训标签**：以“路径展示”的扁平多选（如：门店 / 动作 / 重量）。
  - 导出时自动补齐：
    - 选中某个节点 → 同时包含其所有祖先链（保证可重建树）
    - 选中某个节点 → 同时包含其所有子孙（保证导出的子树完整）

## JSON 格式（两套，互不混用）
- 统一外层结构：
  - `meta`: `schema`、`kind`（training/diet）、`version`、`exportedAt`
  - `tags`: DTO 数组
- **TrainingTag JSON**（树用 parentId 还原）：
  - 每项：`id`、`name`、`level`、`category`（可空）、`parentId`（根为空）
- **DietTag JSON**：
  - 每项：`id`、`name`、`calories`、`protein`、`fat`、`carbs`

## 核心实现（Service 层）
- 新增 `TagImportExportService`（新文件），提供：
  - `exportTrainingTags(context, selectedIds) -> URL`
  - `exportDietTags(context, selectedIds) -> URL`
  - `importTags(from url, context) -> ImportReport`（内部按 meta.kind 分发到 training/diet）
- 编码/解码：使用标准 `Codable + JSONEncoder/JSONDecoder`（当前项目未使用 Codable，但不引入任何三方依赖）。
- Core Data 线程：导入导出均在 `context.perform {}` 或后台 context 中执行，避免跨线程访问。

## 导入去重与合并策略（避免重复标签）
- 基于现有去重逻辑（[Persistence.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Persistence.swift)）保持一致：
  - **优先按 id 命中**（如果导入文件里有 id）
  - 否则按语义键命中：
    - TrainingTag：`level + parent(id/name) + name`
    - DietTag：`name`（trim + lowercased）
- 合并规则：
  - DietTag 营养素采用“补全式合并”（本地为 0 且导入值 > 0 才写入），避免覆盖用户已改数据。
  - TrainingTag 采用“补全式合并”（name/category/parent 缺失才补），关系按 parentId 重建。
- 导入完成后保存 context，并返回导入统计（新增/合并/跳过/失败原因）。

## UI 交互（SwiftUI）
- 在“标签管理”导航栏加一个工具栏菜单（或按钮）：
  - 力训标签：`导出力训标签…`、`导入力训标签…`
  - 饮食标签：`导出饮食标签…`、`导入饮食标签…`
- **导出**：
  - 先弹出选择页 → 生成 json 到临时目录 → 用现有 [ActivityView](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Debug/ActivityView.swift) 打开系统分享（与当前本地数据导出一致模式）。
- **导入**：
  - 使用 `fileImporter` 选择 `.json` 文件 → 解析与写入 Core Data → 弹出结果提示（成功数量/合并数量/错误）。

## 测试与验证
- 新增单元测试（在 `MuscleMetricTests`）：
  - DietTag：导出→导入后数量正确、语义去重不产生重复、营养素“补全式合并”生效。
  - TrainingTag：构造三级树导出→导入后树结构可重建（parentId 对齐），并验证选择导出时“祖先链/子孙”补齐逻辑。
- 手工验证：
  - 在真机/模拟器中：新建若干标签 → 选择部分导出 → 删除本地 → 导入 → 校验 UI 列表与层级恢复。

## 涉及文件（预计改动点）
- 修改：`TagManagerView.swift`（新增工具栏与导入/导出状态管理）
- 新增：`TagImportExportService.swift`（导入导出实现）
- 新增：选择页视图（例如 `TrainingTagExportSelectionView.swift`、`DietTagExportSelectionView.swift`）
- 新增/修改：单元测试文件（`MuscleMetricTests` 目标）