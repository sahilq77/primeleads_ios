<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, PUT, DELETE");
header("Access-Control-Allow-Headers: Content-Type");

// Database connection
$host = "localhost";
$dbname = "portfolio_db";
$username = "root";
$password = "";

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    die(json_encode(["error" => "Connection failed: " . $e->getMessage()]));
}

// Handle API requests
$method = $_SERVER['REQUEST_METHOD'];
$action = isset($_GET['action']) ? $_GET['action'] : '';

switch($action) {
    case 'login':
        if($method === 'POST') {
            $data = json_decode(file_get_contents("php://input"), true);
            $email = $data['email'] ?? '';
            $password = $data['password'] ?? '';
            
            $stmt = $pdo->prepare("SELECT * FROM admins WHERE email = ?");
            $stmt->execute([$email]);
            $admin = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if($admin && password_verify($password, $admin['password'])) {
                echo json_encode([
                    'success' => true,
                    'admin' => ['id' => $admin['id'], 'email' => $admin['email']]
                ]);
            } else {
                echo json_encode(['success' => false, 'message' => 'Invalid credentials']);
            }
        }
        break;

    case 'add_portfolio':
        if($method === 'POST') {
            $data = json_decode(file_get_contents("php://input"), true);
            $title = $data['title'] ?? '';
            $description = $data['description'] ?? '';
            $image = $_FILES['image'] ?? null;

            if($image && $title && $description) {
                $target_dir = "uploads/";
                $image_name = time() . "_" . basename($image["name"]);
                $target_file = $target_dir . $image_name;

                if(move_uploaded_file($image["tmp_name"], $target_file)) {
                    $stmt = $pdo->prepare("INSERT INTO portfolio (title, description, image_path) VALUES (?, ?, ?)");
                    $result = $stmt->execute([$title, $description, $image_name]);
                    
                    echo json_encode([
                        'success' => $result,
                        'message' => $result ? 'Portfolio item added' : 'Failed to add portfolio item'
                    ]);
                } else {
                    echo json_encode(['success' => false, 'message' => 'Failed to upload image']);
                }
            } else {
                echo json_encode(['success' => false, 'message' => 'Missing required fields']);
            }
        }
        break;

    case 'update_portfolio':
        if($method === 'POST') {
            $data = json_decode(file_get_contents("php://input"), true);
            $id = $data['id'] ?? 0;
            $title = $data['title'] ?? '';
            $description = $data['description'] ?? '';
            $image = $_FILES['image'] ?? null;

            if($id && $title && $description) {
                $sql = "UPDATE portfolio SET title = ?, description = ?";
                $params = [$title, $description];

                if($image) {
                    // Delete old image
                    $stmt = $pdo->prepare("SELECT image_path FROM portfolio WHERE id = ?");
                    $stmt->execute([$id]);
                    $item = $stmt->fetch(PDO::FETCH_ASSOC);
                    if($item && file_exists("uploads/" . $item['image_path'])) {
                        unlink("uploads/" . $item['image_path']);
                    }

                    // Upload new image
                    $target_dir = "uploads/";
                    $image_name = time() . "_" . basename($image["name"]);
                    $target_file = $target_dir . $image_name;

                    if(move_uploaded_file($image["tmp_name"], $target_file)) {
                        $sql .= ", image_path = ?";
                        $params[] = $image_name;
                    } else {
                        echo json_encode(['success' => false, 'message' => 'Failed to upload new image']);
                        exit;
                    }
                }

                $sql .= " WHERE id = ?";
                $params[] = $id;

                $stmt = $pdo->prepare($sql);
                $result = $stmt->execute($params);
                
                echo json_encode([
                    'success' => $result,
                    'message' => $result ? 'Portfolio item updated' : 'Failed to update portfolio item'
                ]);
            } else {
                echo json_encode(['success' => false, 'message' => 'Missing required fields']);
            }
        }
        break;

    case 'delete_portfolio':
        if($method === 'DELETE') {
            $data = json_decode(file_get_contents("php://input"), true);
            $id = $data['id'] ?? 0;
            
            // Get image path to delete file
            $stmt = $pdo->prepare("SELECT image_path FROM portfolio WHERE id = ?");
            $stmt->execute([$id]);
            $item = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if($item && unlink("uploads/" . $item['image_path'])) {
                $stmt = $pdo->prepare("DELETE FROM portfolio WHERE id = ?");
                $result = $stmt->execute([$id]);
                
                echo json_encode([
                    'success' => $result,
                    'message' => $result ? 'Portfolio item deleted' : 'Failed to delete portfolio item'
                ]);
            } else {
                echo json_encode(['success' => false, 'message' => 'Failed to delete image']);
            }
        }
        break;

    case 'get_portfolio':
        if($method === 'GET') {
            $stmt = $pdo->prepare("SELECT id, title, description, image_path FROM portfolio ORDER BY id DESC");
            $stmt->execute();
            $items = $stmt->fetchAll(PDO::FETCH_ASSOC);
            
            // Add full image URL for each item
            $items = array_map(function($item) {
                $item['image_url'] = 'uploads/' . $item['image_path'];
                return $item;
            }, $items);
            
            echo json_encode([
                'success' => true,
                'data' => $items
            ]);
        }
        break;

    default:
        echo json_encode(['success' => false, 'message' => 'Invalid action']);
}
?>






<!-- CREATE DATABASE portfolio_db;

USE portfolio_db;

CREATE TABLE admins (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL
);

CREATE TABLE portfolio (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    image_path VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default admin (password: admin123)
INSERT INTO admins (email, password) VALUES 
('admin@example.com', '$2y$10$5z7vXz3Y2J9Qz6nX8mW2O.W7Qz6y8X9mW2O5z7vXz3Y2J9Qz6nX8'); -->