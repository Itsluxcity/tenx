# TenX API Setup Guide

## Required API Keys

You need **TWO** API keys to run TenX:

1. **Claude API Key** (Anthropic) - For AI reasoning, task extraction, and journaling
2. **OpenAI API Key** - For speech-to-text transcription

---

## Step 1: Get Your Claude API Key

### A. Create Anthropic Account
1. Go to: **https://console.anthropic.com/**
2. Click **"Sign Up"** (or "Sign In" if you have an account)
3. Complete the registration

### B. Get API Key
1. Once logged in, go to: **https://console.anthropic.com/settings/keys**
2. Click **"Create Key"**
3. Give it a name like "TenX App"
4. Click **"Create Key"**
5. **COPY THE KEY IMMEDIATELY** - it looks like: `sk-ant-api03-...`
6. Save it somewhere safe (you'll paste it into the app)

### C. Add Credits (if needed)
- Go to: **https://console.anthropic.com/settings/billing**
- Add a payment method
- Anthropic charges per usage (very affordable)
- Recommended: Add $10-20 to start

### Pricing (as of Nov 2025):
- **Claude 3.5 Sonnet**: ~$3 per million input tokens, ~$15 per million output tokens
- For typical use: $0.01-0.05 per conversation
- **Estimate**: $10 can last weeks/months depending on usage

---

## Step 2: Get Your OpenAI API Key

### A. Create OpenAI Account
1. Go to: **https://platform.openai.com/signup**
2. Sign up with email or Google
3. Verify your email

### B. Get API Key
1. Once logged in, go to: **https://platform.openai.com/api-keys**
2. Click **"+ Create new secret key"**
3. Give it a name like "TenX Voice"
4. Click **"Create secret key"**
5. **COPY THE KEY IMMEDIATELY** - it looks like: `sk-proj-...` or `sk-...`
6. Save it somewhere safe

### C. Add Credits
1. Go to: **https://platform.openai.com/settings/organization/billing/overview**
2. Click **"Add payment method"**
3. Add a credit card
4. Recommended: Add $5-10 to start

### Pricing (as of Nov 2025):
- **Whisper (Speech-to-Text)**: $0.006 per minute of audio
- **Example**: 100 minutes of voice notes = $0.60
- **Estimate**: $5 can transcribe ~800 minutes of audio

---

## Step 3: Add Keys to TenX App

### In Xcode:
1. **Build and Run** the app on your iPhone (Cmd + R)
2. The app will launch on your device

### In the TenX App:
1. Tap the **"Settings"** tab (gear icon at bottom)
2. You'll see two fields:
   - **Claude API Key**
   - **OpenAI API Key**

3. **Tap the Claude API Key field**
   - Paste your Claude key (starts with `sk-ant-api03-...`)
   
4. **Tap the OpenAI API Key field**
   - Paste your OpenAI key (starts with `sk-proj-...` or `sk-...`)

5. **Tap "Save API Keys"**

6. **Choose your Claude Model** (optional):
   - **Claude 3.5 Sonnet** ✅ (Recommended - best balance)
   - Claude 3 Opus (Most capable, more expensive)
   - Claude 3 Haiku (Fastest, cheapest)

7. **Configure Behavior** (optional):
   - Toggle **"Auto-add to Calendar/Reminders"**
     - ON = Automatically creates events/reminders
     - OFF = Asks for confirmation first (recommended to start)

---

## Step 4: Grant Permissions

When you first use the app, iOS will ask for permissions:

### Required Permissions:
1. **Microphone** - To record your voice
   - Tap **"Allow"**
   
2. **Calendar** - To create events for meetings/deadlines
   - Tap **"Allow"** or **"Allow Full Access"**
   
3. **Reminders** - To create follow-up reminders
   - Tap **"Allow"** or **"Allow Full Access"**
   
4. **Notifications** - For task alerts
   - Tap **"Allow"**

### If you accidentally denied a permission:
1. Go to iPhone **Settings**
2. Scroll down to **"TenX"**
3. Enable the permissions you need

---

## Step 5: Test It Out!

### First Test - Voice Recording:
1. Go to the **"Chat"** tab
2. **Tap the microphone button** (bottom right)
3. Say: *"I had a meeting with John about the product launch. He said he'll send the specs by next Monday."*
4. **Tap the stop button**
5. Wait a few seconds for transcription
6. Review the text, then **tap Send**

### What Should Happen:
- ✅ Claude processes your message
- ✅ Creates a journal entry for this week
- ✅ Extracts a task: "John to send specs"
- ✅ Sets due date to next Monday
- ✅ Creates a reminder in iOS Reminders app

### Verify:
1. **Tasks Tab** - Should show the new task
2. **Journal Tab** - Should show this week's entry
3. **iOS Reminders App** - Should have a reminder for Monday

---

## Troubleshooting

### "Transcription Failed"
- ❌ **Problem**: OpenAI API key is wrong or has no credits
- ✅ **Fix**: 
  1. Check your OpenAI key in Settings
  2. Verify billing at https://platform.openai.com/settings/organization/billing

### "Claude Not Responding"
- ❌ **Problem**: Claude API key is wrong or has no credits
- ✅ **Fix**:
  1. Check your Claude key in Settings
  2. Verify billing at https://console.anthropic.com/settings/billing

### "Permission Denied"
- ❌ **Problem**: You denied microphone/calendar/reminders access
- ✅ **Fix**:
  1. Go to iPhone Settings → TenX
  2. Enable all permissions

### "Audio Recording Failed"
- ❌ **Problem**: Microphone permission not granted
- ✅ **Fix**: 
  1. Settings → TenX → Microphone → Enable

---

## Cost Estimates

### Light Use (5-10 voice notes per day):
- **OpenAI**: ~$0.50/month (transcription)
- **Claude**: ~$2-5/month (AI processing)
- **Total**: ~$3-6/month

### Heavy Use (20-30 voice notes per day):
- **OpenAI**: ~$2/month
- **Claude**: ~$10-15/month
- **Total**: ~$12-17/month

### Tips to Save Money:
1. Use **Claude 3 Haiku** instead of Sonnet (3x cheaper)
2. Keep voice notes concise
3. Use text input instead of voice when possible

---

## Security Notes

### Where Are Keys Stored?
- Currently: **UserDefaults** (for development)
- **⚠️ Important**: Keys are stored on your device only
- **Never share** your API keys with anyone

### Production Security (Future):
- Keys should be moved to **Keychain** for better security
- This is a personal app, so current storage is acceptable

---

## Quick Reference

| Service | Purpose | URL | Cost |
|---------|---------|-----|------|
| **Anthropic Claude** | AI reasoning & task extraction | https://console.anthropic.com/ | ~$3-15/month |
| **OpenAI Whisper** | Speech-to-text | https://platform.openai.com/ | ~$0.50-2/month |

---

## Next Steps

Once your API keys are set up:

1. ✅ Record a test voice note
2. ✅ Check the Tasks tab
3. ✅ Check the Journal tab
4. ✅ Check iOS Reminders app
5. ✅ Try creating a meeting: "Meeting with Sarah tomorrow at 2pm"
6. ✅ Check iOS Calendar app

**You're all set! Start using TenX to manage your operations like a billionaire. 🚀**
