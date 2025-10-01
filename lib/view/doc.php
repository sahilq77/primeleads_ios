<!-- # Admin API Endpoints

## 1. Admin Login
- **Endpoint**: `POST /admin_api.php?action=login`
- **Request Body**:
  ```json
  {
    "email": "string",
    "password": "string"
  }
  ```
- **Response** (Success):
  ```json
  {
    "success": true,
    "admin": {
      "id": integer,
      "email": "string"
    }
  }
  ```
- **Response** (Error):
  ```json
  {
    "success": false,
    "message": "Invalid credentials"
  }
  ```

## 2. Add Portfolio Item
- **Endpoint**: `POST /admin_api.php?action=add_portfolio`
- **Request Body**: FormData
  ```
  title: string (required)
  description: string (required)
  image: file (required, image/*)
  ```
- **Response** (Success):
  ```json
  {
    "success": true,
    "message": "Portfolio item added"
  }
  ```
- **Response** (Error):
  ```json
  {
    "success": false,
    "message": "Missing required fields" | "Failed to upload image"
  }
  ```

## 3. Update Portfolio Item
- **Endpoint**: `POST /admin_api.php?action=update_portfolio`
- **Request Body**: FormData
  ```
  id: integer (required)
  title: string (required)
  description: string (required)
  image: file (optional, image/*)
  ```
- **Response** (Success):
  ```json
  {
    "success": true,
    "message": "Portfolio item updated"
  }
  ```
- **Response** (Error):
  ```json
  {
    "success": false,
    "message": "Missing required fields" | "Failed to upload new image"
  }
  ```

## 4. Delete Portfolio Item
- **Endpoint**: `DELETE /admin_api.php?action=delete_portfolio`
- **Request Body**:
  ```json
  {
    "id": integer
  }
  ```
- **Response** (Success):
  ```json
  {
    "success": true,
    "message": "Portfolio item deleted"
  }
  ```
- **Response** (Error):
  ```json
  {
    "success": false,
    "message": "Failed to delete image" | "Failed to delete portfolio item"
  }
  ```

## 5. Get Portfolio Items
- **Endpoint**: `GET /admin_api.php?action=get_portfolio`
- **Request Body**: None
- **Response** (Success):
  ```json
  {
    "success": true,
    "data": [
      {
        "id": integer,
        "title": "string",
        "description": "string",
        "image_path": "string",
        "image_url": "string"
      },
      ...
    ]
  }
  ```
- **Response** (Error):
  ```json
  {
    "success": false,
    "message": "Invalid action"
  }
  ```

## Notes
- No authentication headers are required for any endpoint.
- Image uploads must be sent as `multipart/form-data`.
- The `image_url` in the `get_portfolio` response provides the full path to the image (e.g., `uploads/filename.jpg`). -->