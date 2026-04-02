# 删除训练记录确认弹窗贴近被删项 — 实施计划

## 目标
当用户在「训练计划」Tab 的训练记录列表中点击删除时，确认弹窗/提示框应**出现在被删除的那条记录附近**，让用户明确正在删除哪一条数据。

## 背景与约束
- 当前实现使用系统 `confirmationDialog`，在 iPhone 上通常以底部 action sheet 形式出现，**无法保证靠近具体列表项**。
- 为实现“靠近被删项”的效果，需要使用自定义 UI（overlay/popover-like）并将其锚定到对应 row 的屏幕坐标。

## 方案概述（推荐）
在训练记录列表 `PlanTrainingRecordListView` 中实现一个“锚定删除确认浮层”：
1. 为每个 row 通过 `GeometryReader`/`PreferenceKey` 上报其在全局坐标系中的 `CGRect`（按 record.objectID 做 key）。
2. 用户点“删除”时记录 `pendingDeleteId`，并从 frames 字典中取出该 row 的 `CGRect`。
3. 在列表外层 `ZStack` 上叠加一个小浮层（包含：标题/副标题 + “删除/取消”按钮），其 `position` 计算为该 row `CGRect` 的附近（例如右侧或下方），并做边界裁剪防止超出屏幕。
4. 支持点击浮层外区域关闭；滚动/列表刷新时若目标 row 不在屏幕内则自动关闭或重新定位。

## 交互细节
- 删除入口仍保持右滑 `swipeActions`，点击“删除”只打开浮层，不直接删除。
- 浮层内容建议包含：
  - 记录标题（day 名称）
  - 副标题（时间 · 门店）
  - 两个按钮：“删除”（destructive）与“取消”
- 浮层显示时机：
  - 优先贴近该 row（例如 row 右侧居中；若空间不足则放到左侧/下方）。
  - 动画：淡入 + 轻微缩放（避免遮挡过强）。

## 实施步骤
1. **结构调整**
   - 将 `PlanTrainingRecordListView` 的 `List` 包裹在 `ZStack`，为浮层预留 overlay 层。

2. **采集 row 的屏幕坐标**
   - 定义 `PreferenceKey`：`[NSManagedObjectID: Anchor<CGRect>]` 或 `CGRect`（推荐 Anchor 方案更稳定）。
   - 每个 row 通过 `.anchorPreference` 或 `GeometryReader` 将自身 frame 上报到父视图。

3. **实现浮层 UI**
   - 新建一个轻量 View（例如 `DeleteTrainingRecordPopover`），参数包含：标题、副标题、onConfirm、onCancel。
   - 使用 `overlayPreferenceValue` + `GeometryReader` 将 anchor 转为实际 `CGRect`，计算浮层 `position`。
   - 增加外层半透明点击拦截层（`Color.black.opacity(...)` 或 `Color.clear.contentShape(Rectangle())`），点击关闭。

4. **删除逻辑复用**
   - 复用现有 `deletePendingRecord()` 的 CoreData 删除与保存逻辑。
   - 删除成功后关闭浮层并清空 `pendingDeleteId`。

5. **边界与状态处理**
   - 若找不到对应 frame（列表刷新/滚动导致 anchor 丢失）：
     - 回退到系统 `confirmationDialog` 或直接关闭浮层并提示用户重试（推荐回退到系统弹窗，保证可删除）。
   - 滚动时定位更新：
     - 依赖 preference 重新计算；若 row 不可见则自动关闭浮层。

6. **验证**
   - iPhone：删除浮层出现在被删项附近（随滚动位置变化）。
   - iPad：同样靠近被删项（视觉更像 popover）。
   - 删除后列表立即移除该记录，且不崩溃。
   - 编译通过（iOS Simulator）。

## 影响范围
- 主要改动：`MuscleMetric/ContentView.swift` 内 `PlanTrainingRecordListView`（仅 UI/交互层改造，不改 CoreData 模型）。

## 风险与回避
- List 行复用导致 frame 采集不稳定：优先使用 AnchorPreference + overlayPreferenceValue。
- 浮层遮挡列表交互：显示时使用外层拦截层，点击空白关闭。
- 极端屏幕尺寸：位置计算加边界 clamp，避免浮层超出可视区域。

