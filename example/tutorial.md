# Example Tutorial

## Python Setup

Here's the main application:

```python
def main():
    print("Hello from docdriven!")
    return 0

if __name__ == "__main__":
    exit(main())
```

## Database Schema

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE
);
```

## Helper Functions

```python
def greet(name):
    return f"Hello, {name}!"
```

## Frontend Application

```javascript
function App() {
    return (
        <div>
            <h1>Welcome to docdriven!</h1>
            <p>Generated from documentation</p>
        </div>
    );
}

export default App;
```
