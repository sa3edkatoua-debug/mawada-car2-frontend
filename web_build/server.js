const express = require('express');
const cors = require('cors');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());

// 1. ربط قاعدة البيانات
const dbPath = path.join(__dirname, 'vehicles_database.db');
const db = new sqlite3.Database(dbPath);

db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS vehicles (
    id TEXT PRIMARY KEY, model TEXT, color TEXT, plate_number TEXT, owner_name TEXT, entry_time TEXT, is_inside INTEGER DEFAULT 1
  )`);
  db.run(`CREATE TABLE IF NOT EXISTS vehicle_models (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)`);
  db.run(`CREATE TABLE IF NOT EXISTS vehicle_colors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)`);
});

// 2. مشاركة ملفات فلاتر ويب (غيّر المسار إذا كان مجلد فلاتر في مكان آخر)
// نفترض هنا أن مجلد فلاتر موجود بجانب السيرفر أو ضع المسار الكامل لمجلد build/web
app.use(express.static(path.join(__dirname, 'web_build')));

// 3. مسارات الـ APIs
app.get('/api/vehicles', (req, res) => {
  db.all(`SELECT * FROM vehicles ORDER BY entry_time DESC`, [], (err, rows) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(rows.map(r => ({
      id: r.id, model: r.model, color: r.color, plateNumber: r.plate_number,
      ownerName: r.owner_name, entryTime: r.entry_time, isInside: r.is_inside === 1
    })));
  });
});

app.post('/api/vehicles', (req, res) => {
  const { id, model, color, plateNumber, ownerName, entryTime, isInside } = req.body;
  db.run(
    `INSERT INTO vehicles (id, model, color, plate_number, owner_name, entry_time, is_inside) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [id, model, color, plateNumber, ownerName, entryTime, isInside ? 1 : 0],
    (err) => {
      if (err) return res.status(500).json({ error: err.message });
      db.run(`INSERT OR IGNORE INTO vehicle_models (name) VALUES (?)`, [model]);
      db.run(`INSERT OR IGNORE INTO vehicle_colors (name) VALUES (?)`, [color]);
      res.status(201).json({ message: 'Success' });
    }
  );
});

app.put('/api/vehicles/:id/status', (req, res) => {
  db.run(`UPDATE vehicles SET is_inside = ? WHERE id = ?`, [req.body.isInside ? 1 : 0, req.params.id], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ message: 'Updated' });
  });
});

app.get('/api/options', (req, res) => {
  db.all(`SELECT name FROM vehicle_models`, [], (err, models) => {
    db.all(`SELECT name FROM vehicle_colors`, [], (err, colors) => {
      res.json({
        models: (models || []).map(m => m.name),
        colors: (colors || []).map(c => c.name)
      });
    });
  });
});

// توجيه باقي الطلبات لصفحة الويب الرئيسية
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'web_build', 'index.html'));
});

app.listen(3000, '0.0.0.0', () => {
  console.log('السيرفر يعمل الآن وجاهز للاستقبال من المتصفح على Port 3000');
});