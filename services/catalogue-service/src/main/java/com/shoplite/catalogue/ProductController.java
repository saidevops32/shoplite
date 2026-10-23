package com.shoplite.catalogue;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/catalogue")
public class ProductController {

    private static final String COLUMNS = "id, name, description, price_cents, category, emoji, stock";

    private static final RowMapper<Product> MAPPER = (rs, rowNum) -> new Product(
            rs.getInt("id"),
            rs.getString("name"),
            rs.getString("description"),
            rs.getInt("price_cents"),
            rs.getString("category"),
            rs.getString("emoji"),
            rs.getInt("stock"));

    private final JdbcTemplate jdbc;

    public ProductController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    // Every value goes through a ? placeholder, so user input can never become SQL.
    @GetMapping("/products")
    public List<Product> list(@RequestParam(required = false) String q,
                              @RequestParam(required = false) String category) {
        StringBuilder sql = new StringBuilder("SELECT " + COLUMNS + " FROM products WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (q != null && !q.isBlank()) {
            sql.append(" AND (name LIKE ? OR description LIKE ?)");
            String like = "%" + q.trim() + "%";
            args.add(like);
            args.add(like);
        }
        if (category != null && !category.isBlank()) {
            sql.append(" AND category = ?");
            args.add(category.trim());
        }
        sql.append(" ORDER BY id LIMIT 100");
        return jdbc.query(sql.toString(), MAPPER, args.toArray());
    }

    @GetMapping("/products/{id}")
    public ResponseEntity<Product> one(@PathVariable int id) {
        List<Product> rows = jdbc.query("SELECT " + COLUMNS + " FROM products WHERE id = ?", MAPPER, id);
        return rows.isEmpty() ? ResponseEntity.notFound().build() : ResponseEntity.ok(rows.get(0));
    }

    @GetMapping("/categories")
    public List<String> categories() {
        return jdbc.queryForList("SELECT DISTINCT category FROM products ORDER BY category", String.class);
    }
}
