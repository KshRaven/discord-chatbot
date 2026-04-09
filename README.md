# Discord AI Chatbot

A Discord bot powered by Google's Gemini AI featuring advanced conversation threading, automatic rate limiting, robust error handling, image generation, and vision capabilities.

## Prerequisites

- Node.js (v18 or higher)
- npm
- Discord Bot Token
- Google Gemini API Key

## Setup Instructions

### 1. Install Dependencies

```bash
npm install
```

### 2. Get Your API Keys

#### Discord Bot Token:
1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click "New Application" and name it your bot name
3. Go to "Bot" section and click "Add Bot"
4. Under TOKEN, click "Copy" to copy your bot token
5. Make sure these permissions are enabled:
   - Send Messages
   - Create Public Threads
   - Send Messages in Threads
   - View Channels
   - Read Message History

#### Gemini API Key:
1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Click "Create API Key"
3. Copy your API key

## Environment Variables

Create a `.env` file in the project root with these variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DISCORD_TOKEN` | Your Discord bot authentication token | ❌ Required |
| `GEMINI_API_KEY` | Your Google Gemini API key | ❌ Required |
| `GOOGLE_MODEL` | Gemini model to use | `gemini-2.5-flash` |
| `DEBUG` | Enable debug logging (set to any value to enable) | Disabled |

### Example `.env` file:
```env
DISCORD_TOKEN=your_discord_bot_token_here
GEMINI_API_KEY=your_gemini_api_key_here
GOOGLE_MODEL=gemini-2.5-flash
```

**⚠️ Important:** Don't commit the `.env` file (it's added to `.gitignore`)

### 4. Add Bot to Your Discord Server

1. In Developer Portal, go to "OAuth2" → "URL Generator"
2. Select scopes: `bot`
3. Select permissions: 
   - Message Related: `Send Messages`, `Read Message History`
   - Thread Related: `Create Public Threads`, `Send Messages in Threads`, `Manage Threads`
4. Copy the generated URL and open it in your browser
5. Select your server to invite the bot

### 5. Run the Bot

```bash
npm start
```

You should see output like:
```
[timestamp] ℹ️ Environment variables loaded successfully
[timestamp] ℹ️ Using Google AI model: gemini-2.5-flash
[timestamp] ℹ️ Session cleanup scheduler started
[timestamp] ✅ Bot logged in as YourBotName#0000
[timestamp] 📊 Serving X guild(s)
```

## Usage

### Chat with the Bot:
- Mention the bot in a channel: `@BotName your question here`
- The bot automatically creates a thread for your conversation
- Reply in the thread to continue the conversation
- Each user can have up to 5 active threads running simultaneously
- Threads automatically expire after 12 hours of inactivity

### Generate Images:
- Use the command: `!draw a description of what you want`
- Example: `!draw a robot coding in lua`
- Note: Image generation uses a free service (Pollinations.ai)

### Image Analysis:
- Upload an image and ask the bot to analyze it (with or without text)
- Example: `@BotName What's in this image?`

### Conversation Features:
- **Automatic Threading**: Each conversation is organized in its own thread
- **Session Management**: Bot maintains chat history within each thread
- **Rate Limiting**: 50 requests per hour per user to prevent abuse
- **Smart Retries**: Automatic retry with exponential backoff for transient errors
- **Image Support**: Analyze images up to 20MB with vision capabilities
- **Long Responses**: Automatically splits responses to fit Discord's message limit

## Features

### Advanced Capabilities
- **Intelligent Thread Management**: Automatically creates isolated threads for each conversation
- **Session Persistence**: Maintains chat history within threads (resets on new thread)
- **Rate Limiting**: 50 requests/hour per user to prevent spam and API abuse
- **Automatic Retries**: Exponential backoff for transient API failures
- **Error Handling**: Comprehensive error detection and user-friendly messages
- **Memory Management**: Automatic cleanup of old sessions and threads
- **Message Splitting**: Handles long responses by splitting across multiple messages
- **Vision Support**: Analyze images up to 20MB in size
- **Image Generation**: Create images using text prompts

### Configuration Options

The bot uses sensible defaults, but advanced users can customize behavior by modifying the CONFIG object in `index.js`:

- `RESPONSE_CHUNK_SIZE`: Characters per message (default: 1900)
- `SESSION_TIMEOUT`: Session lifetime (default: 1 hour)
- `CLEANUP_INTERVAL`: Memory cleanup frequency (default: 5 minutes)
- `THREAD_LIFETIME`: Thread auto-expiry duration (default: 12 hours)
- `MAX_ACTIVE_THREADS_PER_USER`: Max concurrent threads (default: 5)
- `RATE_LIMIT_THRESHOLD`: Requests per hour per user (default: 50)
- `MAX_IMAGE_SIZE`: Max image file size (default: 20MB)
- `MAX_RETRIES`: Retry attempts for transient errors (default: 3)

## Troubleshooting

### Bot doesn't respond:
- Verify the bot has permissions in the channel (Send Messages, Create Public Threads)
- Check that `DISCORD_TOKEN` and `GEMINI_API_KEY` are correctly set in `.env`
- Run with `DEBUG=1` to see detailed logs: `DEBUG=1 npm start`
- Ensure the bot is mentioned with `@BotName` (not just text in the channel)

### "API Quota Exceeded" error:
- The Gemini free tier allows 20 requests per day
- This limit is shared across all users, so high traffic will trigger it
- Wait until the next day or upgrade your Gemini API plan at https://ai.google.dev
- Consider implementing a quota queue system for production use

### Rate limit warnings:
- You're sending messages too fast (>50 per hour per user)
- The bot will automatically reject requests above this threshold
- Wait a moment before sending your next message

### Image generation fails:
- Image generation uses an external service (Pollinations.ai)
- Check your internet connection
- If the service is down, try again later
- Ensure your prompt is under 500 characters

### "Failed to process image" error:
- Image file might be larger than 20MB
- Image format might not be supported
- Try with a different image file

### Empty response from AI:
- The Gemini API returned an empty response (rare edge case)
- Try your message again
- If persistent, try a different question

### "High demand" errors:
- Gemini API is experiencing high traffic
- The bot will automatically retry with exponential backoff (up to 3 attempts)
- Wait a moment and try again

### Connection timeout:
- Your internet connection might be unstable
- The Discord/Gemini API service might be temporarily down
- Try again in a few moments

### Enable Debug Logging:
Set the `DEBUG` environment variable to see detailed logs:
```bash
DEBUG=1 npm start
```

## Commands Reference

| Interaction | Description | Example |
|------------|-------------|---------|
| `@bot message` | Start a chat conversation | `@BotName How do I use React?` |
| `!draw prompt` | Generate an image from text | `!draw a sunset over mountains` |
| Image + text | Analyze an uploaded image | Upload image + `@BotName what's this?` |
| Reply in thread | Continue conversation | Reply to any bot message in a thread |

## Dependencies

- **discord.js**: Discord API client
- **@google/generative-ai**: Google Gemini API client
- **axios**: HTTP client for image downloads
- **dotenv**: Environment variable loader
