<?php
// Простая страница Hello World с диагностикой ноды/пода Kubernetes.
// Данные о ноде и поде приходят через переменные окружения (см. deployment.yaml, fieldRef/downward API).

$podName   = getenv('POD_NAME')   ?: 'n/a';
$podIP     = getenv('POD_IP')     ?: 'n/a';
$nodeName  = getenv('NODE_NAME')  ?: 'n/a';
$namespace = getenv('POD_NAMESPACE') ?: 'n/a';

$hostname   = gethostname();
$serverAddr = $_SERVER['SERVER_ADDR'] ?? 'n/a';
$remoteAddr = $_SERVER['REMOTE_ADDR'] ?? 'n/a';
$now        = date('Y-m-d H:i:s');
$phpVersion = phpversion();
$loadAvg    = function_exists('sys_getloadavg') ? implode(', ', sys_getloadavg()) : 'n/a';
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Hello World — PHP на Kubernetes</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1e1e2f; color: #f0f0f0; padding: 40px; }
        h1 { color: #61dafb; }
        table { border-collapse: collapse; margin-top: 20px; width: 100%; max-width: 700px; }
        td, th { border: 1px solid #444; padding: 8px 12px; text-align: left; }
        th { background: #2a2a3d; width: 220px; }
        tr:nth-child(even) { background: #26263a; }
    </style>
</head>
<body>
    <h1>👋 Hello World from PHP!</h1>
    <p>Это тестовое приложение, развёрнутое в Kubernetes (minikube).</p>
    <table>
        <tr><th>Имя пода (POD_NAME)</th><td><?= htmlspecialchars($podName) ?></td></tr>
        <tr><th>IP пода (POD_IP)</th><td><?= htmlspecialchars($podIP) ?></td></tr>
        <tr><th>Нода (NODE_NAME)</th><td><?= htmlspecialchars($nodeName) ?></td></tr>
        <tr><th>Namespace</th><td><?= htmlspecialchars($namespace) ?></td></tr>
        <tr><th>Hostname контейнера</th><td><?= htmlspecialchars($hostname) ?></td></tr>
        <tr><th>SERVER_ADDR</th><td><?= htmlspecialchars($serverAddr) ?></td></tr>
        <tr><th>REMOTE_ADDR (клиент)</th><td><?= htmlspecialchars($remoteAddr) ?></td></tr>
        <tr><th>Версия PHP</th><td><?= htmlspecialchars($phpVersion) ?></td></tr>
        <tr><th>Load average</th><td><?= htmlspecialchars($loadAvg) ?></td></tr>
        <tr><th>Текущее время сервера</th><td><?= htmlspecialchars($now) ?></td></tr>
    </table>
</body>
</html>
