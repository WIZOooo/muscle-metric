我将通过用现有的 `AddEntrySheet` 替换当前的 `QuickAddWeightSheet` 来修复点击“+”按钮显示空白页的问题，并配置其预选中当前动作。

**具体步骤：**

1.  **修改 `AddTrainingRecordView.swift` 中的 `AddEntrySheet`**：
    *   添加一个可选属性 `var initialAction: TrainingTag? = nil`。
    *   添加 `.onAppear` 修饰符，如果提供了 `initialAction` 且当前没有选中动作，则将 `selectedAction` 初始化为 `initialAction`。

2.  **更新 `TrainingRecordDetailView.swift`**：
    *   定位到 `.sheet(isPresented: $showQuickAddWeightSheet)` 代码块。
    *   将内容替换为 `AddEntrySheet`。
    *   传入当前的健身房对象 `gym`（从 `record.gymTag` 获取）和初始动作 `initialAction`（从 `quickAddAction` 获取）。
    *   确保 `onSave` 回调闭包使用返回的动作和重量来添加新记录。
    *   删除不再使用的 `QuickAddWeightSheet` 结构体代码。

该方案符合您预期的流程：弹出“添加动作页”，默认选中当前动作，用户选择重量后确认。