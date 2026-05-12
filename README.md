# Mobile Emergency Medical Assistance App - Setup & Running Guide

## Table of Contents
1. [System Overview](#system-overview)
2. [Prerequisites](#prerequisites)
3. [Flutter App Setup](#flutter-app-setup)
4. [Backend Setup](#backend-setup)
5. [Database Setup](#database-setup)
6. [Environment Configuration](#environment-configuration)
7. [Running the System](#running-the-system)
8. [Testing](#testing)
9. [Deployment](#deployment)
10. [Troubleshooting](#troubleshooting)

## System Overview

The Mobile Emergency Medical Assistance App consists of:
- **Flutter Mobile App** (Frontend)
- **Node.js Backend** (REST API + WebSocket)
- **PostgreSQL Database** (Data storage)
- **Real-time Notifications** (WebSocket + Push notifications)

## Prerequisites

### Required Software
- **Node.js** (v18 or higher)
- **npm** (v8 or higher)
- **Flutter** (v3.10 or higher)
- **Dart** (v3.0 or higher)
- **PostgreSQL** (v14 or higher)
- **Git**

### Development Tools
- **VS Code** or similar IDE
- **Postman** or similar API testing tool
- **pgAdmin** or similar database management tool

## Flutter App Setup

### 1. Install Flutter
```bash
# Windows
choco install flutter

# Or download from https://flutter.dev/docs/get-started/install/windows
```

### 2. Verify Installation
```bash
flutter doctor
```

### 3. Install Dependencies
```bash
cd memaap
flutter pub get
```

### 4. Configure Firebase (Optional)
```bash
# If using Firebase for push notifications
# Add google-services.json (Android) and GoogleService-Info.plist (iOS)
```

### 5. Run Flutter App
```bash
# For development
flutter run

# For specific platform
flutter run -d chrome      # Web
flutter run -d windows      # Windows
flutter run -d android      # Android
```

## Backend Setup

### 1. Navigate to Backend Directory
```bash
cd backend
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Install TypeScript Globally (if not installed)
```bash
npm install -g typescript
npm install -g ts-node
npm install -g ts-node-dev
```

### 4. Verify Installation
```bash
npm run build
```

## Database Setup

### 1. Install PostgreSQL
```bash
# Windows
choco install postgresql

# Or download from https://www.postgresql.org/download/windows/
```

### 2. Create Database
```sql
-- Connect to PostgreSQL
psql -U postgres

-- Create database
CREATE DATABASE memaap_db;

-- Create user (optional)
CREATE USER memaap_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE memaap_db TO memaap_user;
```

### 3. Run Database Migrations
```bash
cd backend
npm run migrate
```

### 4. Create Tables (Manual Setup)
```sql
-- Connect to your database
\c memaap_db;

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'patient',
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Hospitals table
CREATE TABLE hospitals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    address TEXT NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    website VARCHAR(255),
    emergency_services JSONB,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Emergency requests table
CREATE TABLE emergency_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    type VARCHAR(50) NOT NULL,
    description TEXT,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    responder_id UUID REFERENCES users(id),
    hospital_id UUID REFERENCES hospitals(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- Notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    data JSONB,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Audit logs table
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    resource VARCHAR(100) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB
);

-- Create indexes
CREATE INDEX idx_emergency_requests_user_id ON emergency_requests(user_id);
CREATE INDEX idx_emergency_requests_status ON emergency_requests(status);
CREATE INDEX idx_emergency_requests_created_at ON emergency_requests(created_at);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp);
```

## Environment Configuration

### 1. Backend Environment Variables
Create `.env` file in `backend/` directory:

```env
# Database Configuration
DATABASE_URL=postgresql://username:password@localhost:5432/memaap_db

# Server Configuration
PORT=3000
NODE_ENV=development

# JWT Configuration
JWT_SECRET=your-super-secret-jwt-key-here
JWT_EXPIRES_IN=24h

# WebSocket Configuration
WS_PORT=3001

# External Services
GOOGLE_MAPS_API_KEY=your-google-maps-api-key
FIREBASE_SERVER_KEY=your-firebase-server-key

# Email Configuration (optional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password

# File Upload
MAX_FILE_SIZE=10485760
UPLOAD_PATH=./uploads

# Logging
LOG_LEVEL=info
LOG_FILE=./logs/app.log
```

### 2. Flutter Environment Configuration
Create `.env` file in `lib/` directory:

```env
# API Configuration
BASE_URL=http://localhost:3000
WS_URL=ws://localhost:3001

# Google Maps
GOOGLE_MAPS_API_KEY=your-google-maps-api-key

# App Configuration
APP_NAME=Memaap Emergency
APP_VERSION=1.0.0
```

## Running the System

### 1. Start Backend Server
```bash
cd backend

# Development mode with auto-restart
npm run dev

# Production mode
npm run build
npm start
```

### 2. Start Flutter App
```bash
# In a new terminal
cd memaap

# Development mode
flutter run

# Web development
flutter run -d chrome --web-port=8080
```

### 3. Verify System is Running
- **Backend**: Visit `http://localhost:3000/api/health`
- **Flutter App**: Should open automatically or visit `http://localhost:8080` (web)
- **WebSocket**: Should connect automatically when app starts

## Testing

### 1. Backend Testing
```bash
cd backend

# Run unit tests
npm test

# Run integration tests
npm run test:integration

# Run with coverage
npm run test:coverage
```

### 2. Flutter Testing
```bash
cd memaap

# Run unit tests
flutter test

# Run widget tests
flutter test integration_test/

# Run with coverage
flutter test --coverage
```

### 3. API Testing (Postman)
Import the following endpoints into Postman:

#### Authentication
- `POST /api/auth/login` - User login
- `POST /api/auth/register` - User registration
- `POST /api/auth/refresh` - Refresh token

#### Emergency Requests
- `POST /api/emergency` - Create emergency request
- `GET /api/emergency/:id` - Get request details
- `PUT /api/emergency/:id/status` - Update request status
- `GET /api/emergency/user/:userId` - Get user requests

#### Hospitals
- `GET /api/hospitals` - Get all hospitals
- `GET /api/hospitals/nearby` - Get nearby hospitals
- `POST /api/hospitals` - Register hospital (admin)

## WebSocket Events

### Client to Server
- `track_request` - Start tracking emergency request
- `location_update` - Send location updates

### Server to Client
- `request_update` - Emergency request status update
- `responder_location` - Responder location update
- `notification` - Push notification

## Troubleshooting

### Common Issues

#### 1. Flutter App Won't Start
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

#### 2. Backend Server Fails to Start
```bash
# Check Node.js version
node --version

# Check dependencies
npm install

# Check database connection
psql -U username -d memaap_db
```

#### 3. Database Connection Issues
```bash
# Verify PostgreSQL is running
pg_ctl status

# Check connection string
psql "postgresql://username:password@localhost:5432/memaap_db"
```

#### 4. WebSocket Connection Fails
- Check if backend is running on correct port
- Verify firewall settings
- Check CORS configuration

#### 5. Location Services Not Working
- Enable location permissions on device
- Check API keys in configuration
- Verify Google Maps API is enabled

### Log Files

#### Backend Logs
- Development: Console output
- Production: `logs/app.log`

#### Flutter Logs
- Development: Flutter console
- Production: Device logs

## Quick Start Checklist

1. ✅ Install Node.js and Flutter
2. ✅ Install PostgreSQL and create database
3. ✅ Clone repository and navigate to project
4. ✅ Run `npm install` in backend directory
5. ✅ Run `flutter pub get` in app directory
6. ✅ Configure environment variables
7. ✅ Start backend: `cd backend && npm run dev`
8. ✅ Start Flutter app: `flutter run`
9. ✅ Test emergency request creation
10. ✅ Verify WebSocket connections

---

**Version**: 1.0.0  
**Last Updated**: 2025-05-11  
**License**: MIT
