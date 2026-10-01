# Vercel deploy

1. Vercel → Add New → Project → herlenjanchiv-creator/kherlen-ghost-detector. repository-г Import хийнэ.
2. Framework: Other. Root Directory: repository root (хоосон).
3. Build Command: npm run build. Output Directory: dist.
4. Environment variables шаардлагагүй. Deploy дарна.

Камер/микрофоныг HTTPS холбоосоор нээнэ. Whisper загвар зөвхөн товч дарсны дараа татагдана. Энэ нь web app; claude-flutter нь тусдаа native эх код бөгөөд Vercel дээр native iPhone app болгон build хийхгүй.
