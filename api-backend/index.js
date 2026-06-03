const express = require('express');
const { Pool } = require('pg');
const app = express();

app.use(express.json());

const PORT = process.env.PORT || 3000;

const pool = new Pool({
 host: process.env.DB_HOST,
 user: process.env.DB_USER,
 database: process.env.DB_NAME,
 password: process.env.DB_PASSWORD,
 port: process.env.DB_PORT || 5432,
});

const initializeDatabase = async () => {
 console.log("Tentative de connexion à la BDD...");
 const client = await pool.connect();
 try {
 await client.query(`
 CREATE TABLE IF NOT EXISTS contacts (
 id SERIAL PRIMARY KEY,
 nom VARCHAR(100) NOT NULL,
 email VARCHAR(100) NOT NULL,
 message TEXT,
 cree_le TIMESTAMP DEFAULT CURRENT_TIMESTAMP
 );
 `);
 console.log("Succès : Table 'contacts' vérifiée/créée.");
 } catch (err) {
 console.error("Erreur critique lors de l'initialisation BDD:", err.message);
 } finally {
 client.release();
 }
};

app.get('/', (req, res) => {
 res.status(200).send('MediTrack API is running');
});

app.get('/contacts', async (req, res) => {
 try {
 const { rows } = await pool.query('SELECT * FROM contacts ORDER BY cree_le DESC');
 res.status(200).json(rows);
 } catch (err) {
 console.error(err.message);
 res.status(500).send('Erreur serveur');
 }
});

app.post('/contact', async (req, res) => {
 const { nom, email, message } = req.body;

 if (!nom || !email) {
 return res.status(400).json({ error: "Le nom et l'email sont requis." });
 }

 try {
 const query = 'INSERT INTO contacts (nom, email, message) VALUES ($1, $2, $3) RETURNING *';
 const { rows } = await pool.query(query, [nom, email, message]);
 res.status(201).json(rows[0]);
 } catch (err) {
 console.error(err.message);
 res.status(500).send('Erreur serveur');
 }
});

app.listen(PORT, () => {
 console.log(`Serveur API démarré sur le port ${PORT}`);
 initializeDatabase();
});