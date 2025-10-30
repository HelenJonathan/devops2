// Minimal app which reads APP_POOL and RELEASE_ID and returns headers used by the grader
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const pool = process.env.APP_POOL || 'unknown';
const release = process.env.RELEASE_ID || 'unknown';
let chaos = false;

app.get('/version', (req, res) => {
    if (chaos) return res.status(500).send('simulated error');
    res.set('X-App-Pool', pool);
    res.set('X-Release-Id', release);
    res.json({ pool, release });
});

app.get('/healthz', (req, res) => res.sendStatus(200));

app.post('/chaos/start', (req, res) => {
    chaos = true;
    res.set('X-App-Pool', pool);
    res.set('X-Release-Id', release);
    res.json({ status: 'chaos started' });
});

app.post('/chaos/stop', (req, res) => {
    chaos = false;
    res.set('X-App-Pool', pool);
    res.set('X-Release-Id', release);
    res.json({ status: 'chaos stopped' });
});

app.listen(port, () => console.log(`app (${pool}:${release}) listening on ${port}`));
app-sample/package.json