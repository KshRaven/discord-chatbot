require('dotenv').config();
const { Client, GatewayIntentBits, Partials } = require('discord.js');
const { GoogleGenerativeAI } = require("@google/generative-ai");
const axios = require('axios');

// ============================================
// CONFIGURATION
// ============================================
const CONFIG = {
  RESPONSE_CHUNK_SIZE: 1900,
  SESSION_TIMEOUT: 60 * 60 * 1000, // 1 hour
  CLEANUP_INTERVAL: 5 * 60 * 1000, // 5 minutes
  THREAD_AUTO_ARCHIVE: 60,
  IMAGE_SIZE: 1024,
  RATE_LIMIT_THRESHOLD: 50, // requests per hour per user
  RATE_LIMIT_WINDOW: 3600 * 1000, // 1 hour
  MAX_IMAGE_SIZE: 20 * 1024 * 1024, // 20MB
  // Retry config for transient errors
  MAX_RETRIES: 3,
  INITIAL_RETRY_DELAY: 1000, // 1 second
  MAX_RETRY_DELAY: 10000, // 10 seconds
  // Thread management
  MAX_ACTIVE_THREADS_PER_USER: 5,
  THREAD_LIFETIME: 60 * 60 * 1000, // 12 hours
};

// ============================================
// LOGGER
// ============================================
const Logger = {
  log: (msg) => console.log(`[${new Date().toISOString()}] ℹ️  ${msg}`),
  info: (msg) => console.log(`[${new Date().toISOString()}] ℹ️  ${msg}`),
  warn: (msg) => console.warn(`[${new Date().toISOString()}] ⚠️  ${msg}`),
  error: (msg, err) => console.error(`[${new Date().toISOString()}] ❌ ${msg}`, err ? err.message : ''),
  debug: (msg) => process.env.DEBUG && console.log(`[${new Date().toISOString()}] 🐛 ${msg}`),
};

// ============================================
// DISCORD CLIENT SETUP
// ============================================
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent
  ],
  partials: [Partials.Channel] // Helps with thread handling
});

// ============================================
// ENVIRONMENT VALIDATION
// ============================================
const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

if (!DISCORD_TOKEN || !GEMINI_API_KEY) {
  Logger.error("Missing environment variables");
  if (!DISCORD_TOKEN) Logger.error("  - DISCORD_TOKEN not found");
  if (!GEMINI_API_KEY) Logger.error("  - GEMINI_API_KEY not found");
  process.exit(1);
}

Logger.log("Environment variables loaded successfully");

// ============================================
// INITIALIZE GEMINI
// ============================================
const GOOGLE_MODEL = process.env.GOOGLE_MODEL || "gemini-2.5-flash";
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: GOOGLE_MODEL });

Logger.log(`Using Google AI model: ${GOOGLE_MODEL}`);

// ============================================
// STATE MANAGEMENT
// ============================================
const userThreads = new Map(); // userId -> [{threadId, createdAt, chatSessionId}, ...]
const chatSessions = new Map(); // sessionId -> ChatSession
const sessionTimestamps = new Map(); // userId -> lastActivity timestamp
const userRateLimits = new Map(); // userId -> [timestamp, request count]
let botUsername = null; // Store bot's own username

// ============================================
// HELPER FUNCTIONS
// ============================================

/**
 * Splits long AI responses to fit Discord's 2000 char limit
 */
async function sendSplit(target, text) {
  if (!text || text.trim().length === 0) {
    Logger.warn("Attempted to send empty message");
    return;
  }
  
  const chunks = [];
  const chunkSize = CONFIG.RESPONSE_CHUNK_SIZE;
  
  // Split by chunks, but be careful not to cut in the middle of sentences/code blocks
  for (let i = 0; i < text.length; i += chunkSize) {
    chunks.push(text.slice(i, i + chunkSize));
  }
  
  Logger.debug(`Sending ${chunks.length} message chunk(s), total length ${text.length} chars`);
  
  // Send each chunk and wait for confirmation
  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    try {
      await target.send(chunk);
      Logger.debug(`Sent chunk ${i + 1}/${chunks.length}`);
    } catch (err) {
      Logger.error(`Failed to send chunk ${i + 1}/${chunks.length}`, err);
      throw new Error(`Failed to send message chunk ${i + 1}: ${err.message}`);
    }
  }
  
  Logger.info(`All ${chunks.length} message chunk(s) sent successfully`);
}

/**
 * Converts Discord attachments to Gemini-friendly format (Vision)
 */
async function fileToGenerativePart(url, mimeType) {
  try {
    Logger.debug(`Processing image: ${url.substring(0, 50)}...`);
    
    const response = await axios.get(url, { 
      responseType: 'arraybuffer',
      timeout: 10000 // 10 second timeout
    });
    
    // Validate file size
    if (response.data.length > CONFIG.MAX_IMAGE_SIZE) {
      throw new Error(`Image too large: ${response.data.length / 1024 / 1024}MB (max 20MB)`);
    }
    
    return {
      inlineData: {
        data: Buffer.from(response.data).toString("base64"),
        mimeType: mimeType || 'image/png'
      },
    };
  } catch (err) {
    Logger.error("Failed to process image attachment", err);
    throw new Error("Could not process image. File may be too large or inaccessible.");
  }
}

/**
 * Rate limiting check - prevents API abuse
 */
function checkRateLimit(userId) {
  const now = Date.now();
  const userLimit = userRateLimits.get(userId) || [now, 0];
  const [windowStart, reqCount] = userLimit;
  
  // Reset window if expired
  if (now - windowStart > CONFIG.RATE_LIMIT_WINDOW) {
    userRateLimits.set(userId, [now, 1]);
    return true;
  }
  
  // Check if over limit
  if (reqCount >= CONFIG.RATE_LIMIT_THRESHOLD) {
    Logger.warn(`Rate limit exceeded for user ${userId}`);
    return false;
  }
  
  // Increment counter
  userRateLimits.set(userId, [windowStart, reqCount + 1]);
  return true;
}

/**
 * Validates user input before sending to Gemini
 */
function validateInput(text, hasAttachments) {
  if (!text && !hasAttachments) {
    return { valid: false, error: "Please include a message or image." };
  }
  if (text && text.length > 4000) {
    return { valid: false, error: "Message too long (max 4000 characters)." };
  }
  return { valid: true };
}

/**
 * Creates or retrieves user's chat session
 */
function getOrCreateChatSession(sessionId) {
  if (!chatSessions.has(sessionId)) {
    Logger.log(`Creating new chat session ${sessionId}`);
    chatSessions.set(sessionId, model.startChat({
      history: [
        { 
          role: "user", 
          parts: [{ text: "You are a professional coding assistant. Keep answers concise and helpful. Focus on code quality and best practices." }] 
        },
        { 
          role: "model", 
          parts: [{ text: "Understood. I'm ready to assist with coding questions, debugging, and image analysis. I'll keep my responses clear and focused." }] 
        },
      ],
    }));
  }
  
  return chatSessions.get(sessionId);
}

/**
 * Generates a unique session ID
 */
function generateSessionId() {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * Gets or creates a thread for a user's message
 * Returns: { threadId, sessionId, channel }
 * @param {Object} message - Discord message object
 * @param {boolean} isBotMentioned - Whether bot was mentioned in a non-thread channel
 */
async function getOrCreateUserThread(message, isBotMentioned = false) {
  const userId = message.author.id;
  const now = Date.now();
  
  // If already in a thread, use that thread
  if (message.channel.isThread()) {
    Logger.debug(`Message already in thread: ${message.channel.id}`);
    
    // Find the session associated with this thread
    const userThreadList = userThreads.get(userId) || [];
    const threadInfo = userThreadList.find(t => t.threadId === message.channel.id);
    
    if (threadInfo) {
      threadInfo.lastActivity = now; // Update last activity
      return {
        threadId: message.channel.id,
        sessionId: threadInfo.sessionId,
        channel: message.channel,
        isNew: false
      };
    }
    
    // Orphaned thread, create new session for it
    const newSessionId = generateSessionId();
    return {
      threadId: message.channel.id,
      sessionId: newSessionId,
      channel: message.channel,
      isNew: true
    };
  }
  
  // Not in a thread - need to get or create one
  let userThreadList = userThreads.get(userId) || [];
  
  // Clean up expired threads
  const threadsToKeep = [];
  for (const t of userThreadList) {
    const age = now - t.lastActivity;
    if (age > CONFIG.THREAD_LIFETIME) {
      Logger.log(`Removing expired thread ${t.threadId} for user ${userId}`);
      chatSessions.delete(t.sessionId); // Clean up session too
      
      // Try to send expiration message and archive thread
      try {
        const channel = await message.client.channels.fetch(t.threadId);
        await channel.send("⏰ **Thread Expired**: This conversation thread has been automatically closed due to inactivity. Start a new conversation to continue.");
        // Archive and lock the thread to remove it from view and prevent further messages
        await channel.setArchived(true);
        await channel.setLocked(true);
        Logger.debug(`Archived and locked expired thread ${t.threadId}`);
      } catch (err) {
        Logger.debug(`Could not cleanup expired thread ${t.threadId}: ${err.message}`);
      }
    } else {
      threadsToKeep.push(t);
    }
  }
  userThreadList = threadsToKeep;
  
  // If bot was mentioned in the channel (not in thread), ALWAYS create new thread
  // Do not reuse threads when bot is explicitly mentioned
  if (isBotMentioned) {
    Logger.debug(`Bot mentioned in channel, creating new thread (skipping reuse logic)`);
  } else if (userThreadList.length > 0) {
    // Only reuse threads if not explicitly mentioned (i.e., user is replying via other means)
    // This won't trigger for normal @mentions from channels
    const lastThread = userThreadList[userThreadList.length - 1];
    const timeSinceLastThread = now - lastThread.lastActivity;
    
    // If last message was within 5 minutes, likely continuing conversation
    if (timeSinceLastThread < 5 * 60 * 1000) {
      try {
        const channel = await message.client.channels.fetch(lastThread.threadId);
        lastThread.lastActivity = now;
        Logger.debug(`Reusing recent thread: ${lastThread.threadId}`);
        return {
          threadId: lastThread.threadId,
          sessionId: lastThread.sessionId,
          channel: channel,
          isNew: false
        };
      } catch (err) {
        Logger.warn(`Could not fetch thread ${lastThread.threadId}, removing it`);
        userThreadList = userThreadList.filter(t => t.threadId !== lastThread.threadId);
      }
    }
  }
  
  // Check if max threads reached - if so, close oldest and create new one
  if (userThreadList.length >= CONFIG.MAX_ACTIVE_THREADS_PER_USER) {
    const oldestThread = userThreadList.shift(); // Remove oldest
    Logger.log(`Max threads (${CONFIG.MAX_ACTIVE_THREADS_PER_USER}) reached for user ${userId}, removing oldest thread ${oldestThread.threadId}`);
    
    // Try to send expiration message
    try {
      const oldChannel = await message.client.channels.fetch(oldestThread.threadId);
      await oldChannel.send("⏰ **Thread Expired**: This conversation thread has been closed due to inactivity or max thread limit. Start a new conversation to continue.");
    } catch (err) {
      Logger.debug(`Could not send expiration message to old thread`);
    }
    
    chatSessions.delete(oldestThread.sessionId);
  }
  
  // Create new thread
  const newSessionId = generateSessionId();
  const newThread = await message.startThread({
    name: `AI Chat - ${message.author.username}`,
    autoArchiveDuration: CONFIG.THREAD_AUTO_ARCHIVE
  });
  
  const threadInfo = {
    threadId: newThread.id,
    sessionId: newSessionId,
    createdAt: now,
    lastActivity: now
  };
  
  userThreadList.push(threadInfo);
  userThreads.set(userId, userThreadList);
  
  Logger.log(`Created new thread ${newThread.id} for user ${userId} (${userThreadList.length}/${CONFIG.MAX_ACTIVE_THREADS_PER_USER} active)`);
  
  return {
    threadId: newThread.id,
    sessionId: newSessionId,
    channel: newThread,
    isNew: true
  };
}

/**
 * Validates image generation request and handles errors gracefully
 */
async function generateImage(prompt, targetChannel) {
  try {
    if (!prompt || prompt.trim().length === 0) {
      return targetChannel.send("Please provide a prompt. Example: `!draw a robot coding in lua`.");
    }
    
    if (prompt.length > 500) {
      return targetChannel.send("Prompt too long (max 500 characters).");
    }
    
    Logger.log(`Generating image with prompt: "${prompt.substring(0, 50)}..."`);
    await targetChannel.sendTyping();
    
    const seed = Math.floor(Math.random() * 10000);
    const imageUrl = `https://pollinations.ai/p/${encodeURIComponent(prompt)}?width=${CONFIG.IMAGE_SIZE}&height=${CONFIG.IMAGE_SIZE}&seed=${seed}`;
    
    // Validate the URL works (basic check)
    try {
      await axios.head(imageUrl, { timeout: 5000 });
    } catch (err) {
      Logger.error("Image generation service unreachable", err);
      return targetChannel.send("❌ Image generation service is temporarily unavailable. Please try again later.");
    }
    
    await targetChannel.send({
      content: `🎨 **Generated Image:** "${prompt}"`,
      files: [{ attachment: imageUrl, name: 'generated.png' }]
    });
    
    Logger.log(`Image generated successfully for prompt: "${prompt.substring(0, 50)}..."`);
  } catch (err) {
    Logger.error("Image generation failed", err);
    await targetChannel.send(`❌ Failed to generate image: ${err.message}`);
  }
}

/**
 * Cleans up old sessions to prevent memory leaks
 */
async function cleanupOldSessions() {
  const now = Date.now();
  let cleanedSessions = 0;
  let cleanedThreads = 0;
  
  // Clean up inactive user threads and sessions
  for (const [userId, threadList] of userThreads.entries()) {
    const threadsToKeep = [];
    
    for (const thread of threadList) {
      const age = now - thread.lastActivity;
      if (age > CONFIG.THREAD_LIFETIME) {
        Logger.debug(`Cleaning up expired thread ${thread.threadId} for user ${userId}`);
        chatSessions.delete(thread.sessionId);
        cleanedSessions++;
        cleanedThreads++;
        
        // Try to send expiration message and archive thread
        try {
          const channel = await client.channels.fetch(thread.threadId);
          await channel.send("⏰ **Thread Expired**: This conversation thread has been automatically closed due to inactivity. Start a new conversation to continue.");
          // Archive and lock the thread to remove it from view and prevent further messages
          await channel.setArchived(true);
          await channel.setLocked(true);
          Logger.debug(`Archived and locked expired thread ${thread.threadId}`);
        } catch (err) {
          Logger.debug(`Could not cleanup expired thread ${thread.threadId}: ${err.message}`);
        }
      } else {
        threadsToKeep.push(thread);
      }
    }
    
    if (threadsToKeep.length === 0) {
      userThreads.delete(userId);
      userRateLimits.delete(userId);
    } else if (threadsToKeep.length !== threadList.length) {
      userThreads.set(userId, threadsToKeep);
    }
  }
  
  if (cleanedThreads > 0 || cleanedSessions > 0) {
    Logger.info(`Cleanup: removed ${cleanedThreads} thread(s), ${cleanedSessions} session(s)`);
  }
}

/**
 * Determines if an error is a quota limit (should not retry)
 */
function isQuotaError(err) {
  const errMsg = err.message?.toLowerCase() || '';
  return errMsg.includes('exceeded your current quota') || errMsg.includes('quota exceeded');
}

/**
 * Determines if an error is transient (should retry) or permanent (should fail)
 */
function isTransientError(err) {
  const errMsg = err.message?.toLowerCase() || '';
  const errStatus = err.response?.status || 0;
  
  // Quota errors are NOT transient - don't retry
  if (isQuotaError(err)) return false;
  
  // Transient errors: should retry
  if (errStatus === 429 || errStatus === 503 || errStatus === 500) return true;
  if (errMsg.includes('timeout')) return true;
  if (errMsg.includes('ECONNREFUSED')) return true;
  if (errMsg.includes('ECONNRESET')) return true;
  if (errMsg.includes('temporarily')) return true;
  if (errMsg.includes('overloaded')) return true;
  if (errMsg.includes('high demand')) return true;
  
  return false;
}

/**
 * Retries a function with exponential backoff for transient errors
 */
async function retryWithBackoff(fn, operationName = 'Operation') {
  let lastErr;
  let delay = CONFIG.INITIAL_RETRY_DELAY;
  
  for (let attempt = 1; attempt <= CONFIG.MAX_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      
      // Check if error is transient
      if (!isTransientError(err)) {
        Logger.debug(`${operationName}: Permanent error, not retrying`);
        throw err;
      }
      
      // If last attempt, throw
      if (attempt === CONFIG.MAX_RETRIES) {
        Logger.warn(`${operationName}: Failed after ${CONFIG.MAX_RETRIES} retries`);
        throw err;
      }
      
      // Wait before retrying
      Logger.warn(`${operationName}: Attempt ${attempt} failed (${err.message}), retrying in ${delay}ms...`);
      await new Promise(resolve => setTimeout(resolve, delay));
      
      // Exponential backoff: increase delay for next attempt
      delay = Math.min(delay * 2, CONFIG.MAX_RETRY_DELAY);
    }
  }
  
  throw lastErr;
}

// ============================================
// MEMORY CLEANUP SCHEDULER
// ============================================
setInterval(() => {
  cleanupOldSessions();
}, CONFIG.CLEANUP_INTERVAL);

Logger.log("Session cleanup scheduler started");

// ============================================
// MESSAGE HANDLER
// ============================================
client.on('messageCreate', async (message) => {
  // Ignore bot messages
  if (message.author.bot) {
    return;
  }

  Logger.debug(`Message from ${message.author.username}: "${message.content.substring(0, 50)}..."`);

  // Check if bot is mentioned OR if this is in a bot-created thread
  const isBotMentioned = message.mentions.has(client.user);
  const userThreadList = userThreads.get(message.author.id) || [];
  const isBotThread = message.channel.isThread() && userThreadList.some(t => t.threadId === message.channel.id);
  
  if (!isBotMentioned && !isBotThread) {
    Logger.debug("Bot not mentioned and not in bot thread, ignoring message");
    return;
  }

  try {
    // Rate limiting check
    if (!checkRateLimit(message.author.id)) {
      Logger.warn(`Rate limit triggered for ${message.author.id}`);
      return message.reply("⏱️ You're sending messages too fast. Please wait a moment before trying again.");
    }

    // ============================================
    // THREAD MANAGEMENT SYSTEM
    // ============================================
    const threadInfo = await getOrCreateUserThread(message, isBotMentioned);
    const targetChannel = threadInfo.channel;
    const sessionId = threadInfo.sessionId;
    
    Logger.debug(`Using thread ${threadInfo.threadId}, session ${sessionId} (isNew: ${threadInfo.isNew})`);

    // Remove bot mention from text
    const cleanText = message.content.replace(/<@!?\d+>/g, '').trim();

    // ============================================
    // IMAGE GENERATION COMMAND
    // ============================================
    if (cleanText.toLowerCase().startsWith('!draw')) {
      const prompt = cleanText.replace(/!draw/i, '').trim();
      return generateImage(prompt, targetChannel);
    }

    // ============================================
    // INPUT VALIDATION
    // ============================================
    const validation = validateInput(cleanText, message.attachments.size > 0);
    if (!validation.valid) {
      Logger.warn(`Invalid input from ${message.author.id}: ${validation.error}`);
      return targetChannel.send(`❌ ${validation.error}`);
    }

    // ============================================
    // GET OR CREATE CHAT SESSION
    // ============================================
    const chat = getOrCreateChatSession(sessionId);
    
    await targetChannel.sendTyping();

    // ============================================
    // BUILD MESSAGE PAYLOAD
    // ============================================
    let payload = [cleanText || "Analyze this image"];
    
    if (message.attachments.size > 0) {
      Logger.log(`Processing ${message.attachments.size} attachment(s) from ${message.author.id}`);
      const imageParts = await Promise.all(
        Array.from(message.attachments.values()).map(a => fileToGenerativePart(a.url, a.contentType))
      );
      payload = [...imageParts, cleanText || "What is in this image?"];
    }

    // ============================================
    // SEND TO GEMINI AND REPLY
    // ============================================
    Logger.log(`Sending message to Gemini for session ${sessionId}`);
    
    let reply;
    try {
      // Send to Gemini with retry logic for transient errors
      const result = await retryWithBackoff(
        async () => {
          return await chat.sendMessage(payload);
        },
        `Chat message from session ${sessionId}`
      );
      
      const response = await result.response;
      reply = response.text();

      if (!reply || reply.trim().length === 0) {
        Logger.error("Empty response from Gemini");
        return targetChannel.send("❌ Received empty response from AI. Please try again.");
      }

      Logger.info(`Gemini response: ${reply.length} characters`);
      await sendSplit(targetChannel, reply);
      Logger.log(`Response sent successfully to session ${sessionId}`);
      
    } catch (geminiErr) {
      Logger.error(`Gemini API error for session ${sessionId}`, geminiErr);
      
      // Check for quota errors first
      if (isQuotaError(geminiErr)) {
        return targetChannel.send("❌ **API Quota Exceeded**: The Gemini API free tier daily limit (20 requests) has been reached. Please wait until tomorrow or upgrade your API plan at https://ai.google.dev/");
      }
      
      // Determine if it's a temporary issue or permanent
      if (isTransientError(geminiErr)) {
        return targetChannel.send("⏠️ Gemini API is temporarily unavailable due to high demand. Please try again in a moment.");
      } else if (geminiErr.message.includes('not found') || geminiErr.message.includes('not supported')) {
        return targetChannel.send("❌ The AI model is not available. Please contact the bot owner to update the model.");
      } else {
        return targetChannel.send("❌ AI responded with an error. Please try again.");
      }
    }

  } catch (err) {
    Logger.error(`Message processing error for user ${message.author.id}`, err);
    
    // Determine appropriate error message
    let errorMsg = "❌ An error occurred";
    
    if (err.message.includes('rate limit') || err.message.includes('429')) {
      errorMsg = "⏱️ API rate limited. Please wait a moment and try again.";
    } else if (err.message.includes('timeout') || err.message.includes('ECONNREFUSED')) {
      errorMsg = "⏠️ Connection timeout. Please try again in a moment.";
    } else if (err.message.includes('401') || err.message.includes('403')) {
      errorMsg = "❌ Authentication error. Please check your API keys.";
    } else if (err.message.includes('503') || err.message.includes('500')) {
      errorMsg = "⏠️ Service temporarily unavailable. Please try again later.";
    } else if (err.message.includes('image')) {
      errorMsg = `❌ Image error: ${err.message}`;
    } else if (err.message.includes('Failed to send message')) {
      errorMsg = "❌ Failed to send response. Please try again.";
    }
    
    try {
      await message.reply(errorMsg);
    } catch (replyErr) {
      Logger.error("Failed to send error message", replyErr);
    }
  }
});

// ============================================
// BOT READY EVENT
// ============================================
client.once('ready', () => {
  botUsername = client.user.username;
  Logger.log(`✅ Bot logged in as ${client.user.tag}`);
  Logger.log(`📊 Serving ${client.guilds.cache.size} guild(s)`);
  Logger.log(`🤖 Bot username: ${botUsername}`);
  client.user.setActivity('your messages', { type: 'LISTENING' });
});

// ============================================
// ERROR HANDLERS
// ============================================
client.on('error', (err) => {
  Logger.error("Discord client error", err);
});

process.on('unhandledRejection', (reason, promise) => {
  Logger.error("Unhandled rejection", reason);
});

// ============================================
// LOGIN
// ============================================
Logger.log("Starting bot...");
client.login(DISCORD_TOKEN);