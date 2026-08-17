CREATE TABLE elements (
    id INT AUTO_INCREMENT PRIMARY KEY,
    problem_id INT NOT NULL,
    type ENUM('text', 'image', 'answer_blank', 'imported_block') NOT NULL,
    pos_x INT NOT NULL DEFAULT 0,
    pos_y INT NOT NULL DEFAULT 0,
    width INT NOT NULL DEFAULT 200,
    height INT DEFAULT NULL,
    content TEXT,
    raw_content MEDIUMTEXT,
    correct_value VARCHAR(500) DEFAULT NULL,
    tolerance VARCHAR(100) DEFAULT NULL,
    z_index INT NOT NULL DEFAULT 0,
    FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE
) DEFAULT CHARACTER SET utf8mb4;