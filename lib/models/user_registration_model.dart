/// Model class for user registration data
/// 
/// Contains all required fields for user registration in the
/// Mobile Emergency Medical Assistance App.
class UserRegistrationModel {
  final String name;
  final String phone;
  final String? email;
  final String password;
  final String confirmPassword;
  final String role;

  UserRegistrationModel({
    required this.name,
    required this.phone,
    this.email,
    required this.password,
    required this.confirmPassword,
    required this.role,
  });

  /// Creates a copy of this model with updated values
  UserRegistrationModel copyWith({
    String? name,
    String? phone,
    String? email,
    String? password,
    String? confirmPassword,
    String? role,
  }) {
    return UserRegistrationModel(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      role: role ?? this.role,
    );
  }

  /// Converts the model to a JSON map for API requests
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      if (email != null && email!.isNotEmpty) 'email': email,
      'password': password,
      'role': role,
    };
  }

  /// Creates a UserRegistrationModel from a JSON map
  factory UserRegistrationModel.fromJson(Map<String, dynamic> json) {
    return UserRegistrationModel(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      password: json['password'] ?? '',
      confirmPassword: json['confirmPassword'] ?? json['password'] ?? '',
      role: json['role'] ?? 'patient',
    );
  }

  @override
  String toString() {
    return 'UserRegistrationModel(name: $name, phone: $phone, email: $email, role: $role)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserRegistrationModel &&
        other.name == name &&
        other.phone == phone &&
        other.email == email &&
        other.password == password &&
        other.confirmPassword == confirmPassword &&
        other.role == role;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        phone.hashCode ^
        email.hashCode ^
        password.hashCode ^
        confirmPassword.hashCode ^
        role.hashCode;
  }
}
