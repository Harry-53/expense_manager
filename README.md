# expense_manager

A new Flutter personal project.

## File Structure

lib/
├── main.dart
├── app.dart
│
├── core/
│   ├── constants.dart
│   ├── encryption.dart
│   ├── ml/
│   │   ├── category_model.dart
│   │   └── sample_training_data.json
│
├── data/
│   ├── models/
│   │   └── transaction_model.dart
│   ├── parsers/
│   │   └── bank_sms_parser.dart
│   ├── repositories/
│   │   └── firebase_transaction_repository.dart
│
├── domain/
│   ├── entities/
│   │   └── transaction_entity.dart
│   └── repositories/
│       └── transaction_repository.dart
│
├── presentation/
│   ├── dashboard/
│   │   └── dashboard.dart
│
android/
└── app/
    ├── src/main/java/.../widget/
    │   └── ExpenseWidget.kt
    └── res/layout/
        └── widget_expense.xml
