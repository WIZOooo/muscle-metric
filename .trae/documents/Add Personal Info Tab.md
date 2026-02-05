我将在应用中新增一个“个人信息”标签页，使用 Core Data 和 CloudKit 存储用户数据，确保数据同步到 iCloud。根据您的最新要求，将移除姓名，并增加身高和体重信息。

### 实现计划

1.  **扩展数据模型 (Core Data)**：
    - 修改 `MuscleMetric.xcdatamodeld` 文件，新增实体 `UserProfile`。
    - 属性包括：
        - `id` (UUID)
        - `age` (Integer 16, 年龄)
        - `gender` (String, 性别)
        - `goal` (String, 运动目标)
        - `height` (Double, 身高，单位 cm)
        - `weight` (Double, 体重，单位 kg)
    - 创建对应的模型类文件 `Model/UserProfile+CoreDataClass.swift`。

2.  **创建个人信息视图**：
    - 创建新目录 `MuscleMetric/Views/PersonalInfo`。
    - 创建 `PersonalInfoView.swift`。
    - 实现逻辑：自动获取或创建唯一的 `UserProfile` 记录。
    - 界面包含（支持编辑）：
        - **基本资料**：年龄、性别。
        - **身体数据**：身高、体重。
        - **目标设定**：运动目标（增肌/减脂）。
    - 数据修改即时保存到 Core Data。

3.  **集成到主界面**：
    - 修改 `ContentView.swift`，加入“个人信息”标签页。
    - 设置标签名为“个人信息”，图标为 `person.circle`。

### 验证计划
- 运行应用，验证界面包含年龄、性别、身高、体重、运动目标字段。
- 输入数据并重启，确认数据持久化保存。
