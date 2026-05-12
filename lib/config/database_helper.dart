import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton class that manages the local SQLite database for the
/// Mobile Emergency Medical Assistance App.
/// 
/// Handles table creation, schema migrations, and CRUD operations for
/// offline storage of users, emergency requests, and hospital data.
/// 
/// This class follows the singleton pattern to ensure only one database
/// connection exists throughout the app lifecycle.
class DatabaseHelper {
  // Singleton instance
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// Database instance
  static Database? _database;

  /// Database version for migrations
  static const int _databaseVersion = 1;

  /// Database name
  static const String _databaseName = 'memaap.db';

  /// Table names
  static const String tableUsers = 'users';
  static const String tableEmergencyRequests = 'emergency_requests';
  static const String tableCachedHospitals = 'cached_hospitals';

  /// Column names for users table
  static const String colUserId = 'id';
  static const String colUserName = 'name';
  static const String colUserPhone = 'phone';
  static const String colUserEmail = 'email';
  static const String colUserMedicalInfo = 'medical_info';
  static const String colUserCreatedAt = 'created_at';
  static const String colUserUpdatedAt = 'updated_at';

  /// Column names for emergency_requests table
  static const String colRequestId = 'id';
  static const String colRequestUserId = 'user_id';
  static const String colRequestType = 'type';
  static const String colRequestDescription = 'description';
  static const String colRequestLatitude = 'latitude';
  static const String colRequestLongitude = 'longitude';
  static const String colRequestStatus = 'status';
  static const String colRequestCreatedAt = 'created_at';
  static const String colRequestUpdatedAt = 'updated_at';

  /// Column names for cached_hospitals table
  static const String colHospitalId = 'id';
  static const String colHospitalName = 'name';
  static const String colHospitalLatitude = 'latitude';
  static const String colHospitalLongitude = 'longitude';
  static const String colHospitalAddress = 'address';
  static const String colHospitalPhone = 'phone';
  static const String colHospitalEmergencyServices = 'emergency_services';
  static const String colHospitalCachedAt = 'cached_at';

  /// Initializes the database and creates tables if they don't exist
  /// 
  /// Returns the [Database] instance. Creates the database file if it doesn't exist
  /// and runs any necessary migrations.
  /// 
  /// Throws [Exception] if database initialization fails.
  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  /// Initializes the database with proper schema and migrations
  /// 
  /// [path] - The database file path
  /// 
  /// Returns the initialized [Database] instance
  Future<Database> _initDB() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _databaseName);

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );
    } catch (e) {
      throw Exception('Failed to initialize database: $e');
    }
  }

  /// Configures database settings (enables foreign keys)
  /// 
  /// [db] - The database instance to configure
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Creates database tables when the database is first created
  /// 
  /// [db] - The database instance
  /// [version] - The database version
  Future<void> _onCreate(Database db, int version) async {
    try {
      // Create users table
      await db.execute('''
        CREATE TABLE $tableUsers (
          $colUserId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colUserName TEXT NOT NULL,
          $colUserPhone TEXT NOT NULL UNIQUE,
          $colUserEmail TEXT UNIQUE,
          $colUserMedicalInfo TEXT,
          $colUserCreatedAt TEXT NOT NULL,
          $colUserUpdatedAt TEXT NOT NULL
        )
      ''');

      // Create emergency_requests table
      await db.execute('''
        CREATE TABLE $tableEmergencyRequests (
          $colRequestId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colRequestUserId INTEGER NOT NULL,
          $colRequestType TEXT NOT NULL,
          $colRequestDescription TEXT,
          $colRequestLatitude REAL NOT NULL,
          $colRequestLongitude REAL NOT NULL,
          $colRequestStatus TEXT NOT NULL DEFAULT 'pending',
          $colRequestCreatedAt TEXT NOT NULL,
          $colRequestUpdatedAt TEXT NOT NULL,
          FOREIGN KEY ($colRequestUserId) REFERENCES $tableUsers ($colUserId) ON DELETE CASCADE
        )
      ''');

      // Create cached_hospitals table
      await db.execute('''
        CREATE TABLE $tableCachedHospitals (
          $colHospitalId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colHospitalName TEXT NOT NULL,
          $colHospitalLatitude REAL NOT NULL,
          $colHospitalLongitude REAL NOT NULL,
          $colHospitalAddress TEXT,
          $colHospitalPhone TEXT,
          $colHospitalEmergencyServices TEXT,
          $colHospitalCachedAt TEXT NOT NULL
        )
      ''');

      // Create indexes for better performance
      await db.execute('CREATE INDEX idx_users_phone ON $tableUsers ($colUserPhone)');
      await db.execute('CREATE INDEX idx_requests_user_id ON $tableEmergencyRequests ($colRequestUserId)');
      await db.execute('CREATE INDEX idx_requests_status ON $tableEmergencyRequests ($colRequestStatus)');
      await db.execute('CREATE INDEX idx_hospitals_location ON $tableCachedHospitals ($colHospitalLatitude, $colHospitalLongitude)');

    } catch (e) {
      throw Exception('Failed to create database tables: $e');
    }
  }

  /// Handles database schema migrations
  /// 
  /// [db] - The database instance
  /// [oldVersion] - The current database version
  /// [newVersion] - The target database version
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    try {
      // Add migration logic here when database version changes
      // Example: if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
      
      // For now, since we're at version 1, no migrations are needed
    } catch (e) {
      throw Exception('Failed to migrate database from version $oldVersion to $newVersion: $e');
    }
  }

  /// Inserts a record into the specified table
  /// 
  /// [table] - The target table name
  /// [data] - Map containing column names and values
  /// 
  /// Returns the ID of the inserted record
  /// 
  /// Throws [Exception] if the insert operation fails
  Future<int> insertRecord(String table, Map<String, dynamic> data) async {
    try {
      final db = await database;
      return await db.insert(table, data);
    } catch (e) {
      throw Exception('Failed to insert record into $table: $e');
    }
  }

  /// Retrieves records from the specified table
  /// 
  /// [table] - The target table name
  /// [where] - Optional WHERE clause
  /// [whereArgs] - Optional arguments for the WHERE clause
  /// [orderBy] - Optional ORDER BY clause
  /// [limit] - Optional LIMIT clause
  /// 
  /// Returns a list of maps representing the records
  /// 
  /// Throws [Exception] if the query operation fails
  Future<List<Map<String, dynamic>>> getRecords(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    try {
      final db = await database;
      return await db.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
      );
    } catch (e) {
      throw Exception('Failed to retrieve records from $table: $e');
    }
  }

  /// Updates records in the specified table
  /// 
  /// [table] - The target table name
  /// [data] - Map containing column names and values to update
  /// [where] - WHERE clause to identify records to update
  /// [whereArgs] - Arguments for the WHERE clause
  /// 
  /// Returns the number of affected rows
  /// 
  /// Throws [Exception] if the update operation fails
  Future<int> updateRecord(
    String table,
    Map<String, dynamic> data,
    String where,
    List<dynamic> whereArgs,
  ) async {
    try {
      final db = await database;
      return await db.update(table, data, where: where, whereArgs: whereArgs);
    } catch (e) {
      throw Exception('Failed to update records in $table: $e');
    }
  }

  /// Deletes records from the specified table
  /// 
  /// [table] - The target table name
  /// [where] - WHERE clause to identify records to delete
  /// [whereArgs] - Arguments for the WHERE clause
  /// 
  /// Returns the number of affected rows
  /// 
  /// Throws [Exception] if the delete operation fails
  Future<int> deleteRecord(String table, String where, List<dynamic> whereArgs) async {
    try {
      final db = await database;
      return await db.delete(table, where: where, whereArgs: whereArgs);
    } catch (e) {
      throw Exception('Failed to delete records from $table: $e');
    }
  }

  /// Executes a raw SQL query
  /// 
  /// [sql] - The SQL query to execute
  /// [arguments] - Optional arguments for the query
  /// 
  /// Returns a list of maps representing the query results
  /// 
  /// Throws [Exception] if the query operation fails
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? arguments]) async {
    try {
      final db = await database;
      return await db.rawQuery(sql, arguments);
    } catch (e) {
      throw Exception('Failed to execute raw query: $e');
    }
  }

  /// Closes the database connection
  /// 
  /// Should be called when the app is shutting down
  Future<void> closeDB() async {
    try {
      final db = _database;
      if (db != null) {
        await db.close();
        _database = null;
      }
    } catch (e) {
      throw Exception('Failed to close database: $e');
    }
  }

  /// Deletes the database file
  /// 
  /// Useful for testing or resetting the app data
  /// 
  /// Returns true if the database was successfully deleted
  Future<bool> deleteDatabase() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _databaseName);
      
      await closeDB();
      await databaseFactory.deleteDatabase(path);
      return true;
    } catch (e) {
      throw Exception('Failed to delete database: $e');
    }
  }

  /// Gets the current database version
  /// 
  /// Returns the database version number
  Future<int> getDatabaseVersion() async {
    try {
      final db = await database;
      final result = await db.rawQuery('PRAGMA user_version');
      return result.first['user_version'] as int;
    } catch (e) {
      throw Exception('Failed to get database version: $e');
    }
  }
}
