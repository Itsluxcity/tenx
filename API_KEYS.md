# API Keys Setup

**IMPORTANT**: This app requires API keys to function. Your API keys are NOT included in this repository for security.

## Required API Keys

### 1. Claude API Key (Anthropic)
- Get your key from: https://console.anthropic.com/
- The app uses Claude for AI processing and the multi-agent system

### 2. OpenAI API Key (Optional)
- Get your key from: https://platform.openai.com/
- Used for audio transcription with Whisper

## How to Add Your Keys

1. Open the app
2. Go to **Settings** tab
3. Enter your API keys in the appropriate fields:
   - **Claude API Key**: Paste your `sk-ant-api03-...` key
   - **OpenAI API Key**: Paste your `sk-proj-...` key (optional)
4. The keys will be saved securely in UserDefaults

## Security Note

- **NEVER** commit your API keys to Git
- The `.gitignore` is configured to prevent accidental commits
- Keys are stored locally on your device only
- If you fork this repo, make sure your keys stay private

## First-Time Setup

After cloning this repository:
1. Build and run the app
2. You'll see empty fields in Settings
3. Add your API keys
4. Start using the app!

The app will remember your keys for future sessions.
