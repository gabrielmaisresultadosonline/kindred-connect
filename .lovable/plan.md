I will implement the complete ZAPMRO CLOUD system as described in the documentation, ensuring it is ready for deployment on a Linux environment (Ubuntu 24 LTS).

### 1. Project Infrastructure
- Create the directory structure: `Server/`, `Public/`, `data/`, `data/history/`, `data/archives/`, `Public/uploads/`.
- Initialize `package.json` with all required dependencies (`express`, `socket.io`, `whatsapp-web.js`, `axios`, `dotenv`, `fluent-ffmpeg`, `ffmpeg-static`, `multer`, etc.).
- Set up `.env` with the necessary configuration variables.

### 2. Backend Implementation (`Server/`)
- **`proxyManager.js`**: Implement the proxy distribution and persistence logic.
- **`index.js`**: Build the core server. This includes:
  - Express server and Socket.IO initialization.
  - Authentication logic (User/Admin) with local JSON persistence.
  - WhatsApp client management using `whatsapp-web.js` (initializing clients, handling QR codes, authentication, and events).
  - CRM logic: Chat history, Kanban status, tags, and contact management.
  - Automation engine: Handling flows (keywords, steps, delays).
  - AI Integration: Connecting to DeepSeek/OpenAI for automated responses and transcription.
  - Google Integration: OAuth2 flow and People API for contact synchronization.
  - Scheduling: Logic for scheduled messages and WinBack campaigns.
  - Media Handling: Uploading and converting audio files using FFmpeg.

### 3. Frontend Implementation (`Public/`)
- **`index.html` & `app.js`**: Landing page for authentication and session management.
- **`crm.html` & `crm.js`**: Main dashboard featuring the Kanban board, WhatsApp chat interface, Flow builder, AI settings, Agenda, and WinBack campaign manager.
- **`politica.html` & `termos.html`**: Basic legal pages.

### 4. Persistence Layer (`data/`)
- Create initial empty JSON files for all data structures (users, sessions, flows, tags, etc.) to ensure the system starts correctly.

### 5. Final Configuration
- Set up the execution scripts (`start`, `dev`) in `package.json`.
- Ensure all file paths are consistent (standardizing on `Server/` and `Public/`).

### Technical Details
- **Environment**: Ubuntu 24 LTS (Linux).
- **Runtime**: Node.js / Bun.
- **Persistence**: Local JSON files (no external DB required as per documentation).
- **WhatsApp**: `whatsapp-web.js` with Puppeteer.
- **AI**: DeepSeek/OpenAI.
- **Google**: OAuth2 + People API.