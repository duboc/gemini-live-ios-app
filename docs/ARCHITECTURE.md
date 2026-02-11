# Architecture Documentation

## Overview
This document describes the architectural decisions and patterns used in [App Name].

## Architecture Pattern: MVVM with @Observable

### Layer Structure
```
┌─────────────────────────────────────────┐
│              Views (SwiftUI)            │
├─────────────────────────────────────────┤
│           ViewModels (@Observable)      │
├─────────────────────────────────────────┤
│              Services                   │
├─────────────────────────────────────────┤
│           Data Layer / Models           │
└─────────────────────────────────────────┘
```

## Key Patterns

### View Layer
- Pure SwiftUI views
- No business logic
- Minimal state management
- Declarative UI definition

### ViewModel Layer
- `@Observable` macro for state management
- Business logic and data transformation
- Async/await for all async operations
- Protocol-based dependencies for testing

### Service Layer
- Network requests
- Persistence operations
- Third-party integrations
- Actor-based for thread safety

### Data Layer
- SwiftData models
- Value types (structs) for DTOs
- Codable conformance

## Navigation

### Approach: NavigationStack with Type-Safe Routes
```swift
enum AppRoute: Hashable {
    case home
    case detail(Item)
    case settings
    case profile(User)
}
```

### Router Pattern
```swift
@Observable
final class Router {
    var path = NavigationPath()
    
    func navigate(to route: AppRoute) {
        path.append(route)
    }
    
    func popToRoot() {
        path = NavigationPath()
    }
}
```

## Dependency Injection

### Approach: Environment-Based DI
```swift
struct ServiceContainer: EnvironmentKey {
    static let defaultValue = ServiceContainer()
    
    let networkService: NetworkServiceProtocol
    let storageService: StorageServiceProtocol
    
    init(
        networkService: NetworkServiceProtocol = NetworkService(),
        storageService: StorageServiceProtocol = StorageService()
    ) {
        self.networkService = networkService
        self.storageService = storageService
    }
}
```

## Error Handling

### Typed Errors
```swift
enum AppError: LocalizedError {
    case network(NetworkError)
    case validation(String)
    case persistence(Error)
    
    var errorDescription: String? { ... }
}
```

## Testing Strategy

### Unit Tests
- All ViewModels tested
- Mock services for isolation
- Swift Testing framework

### UI Tests
- Critical user flows
- Accessibility testing
- Screenshot testing for regressions

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| YYYY-MM-DD | Use @Observable over ObservableObject | Modern approach, less boilerplate, better performance |
| YYYY-MM-DD | SwiftData for persistence | Native solution, better SwiftUI integration |
