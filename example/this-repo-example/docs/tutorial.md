# My Project Tutorial

## Main Application

This is the entry point for our application:

```python
def main():
    print("Hello from docdriven!")
    print("Running in the same repository as the docs!")
    return 0

if __name__ == "__main__":
    exit(main())
```

## Utility Functions

Helper functions for the application:

```python
def calculate_sum(a, b):
    """Add two numbers together."""
    return a + b

def greet(name):
    """Greet a user by name."""
    return f"Hello, {name}!"
```

## Database Schema

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
```
