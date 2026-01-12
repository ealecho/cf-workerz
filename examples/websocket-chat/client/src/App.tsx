import { useRef, useEffect, FormEvent, useState } from 'react';
import { useChat } from './hooks/useChat';

const WS_URL = import.meta.env.VITE_WS_URL || 'ws://localhost:8787/ws';

function App() {
  const { messages, status, sendMessage, currentUserId, isSystemMessage } = useChat(WS_URL);
  const [input, setInput] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (input.trim() && status === 'connected') {
      sendMessage(input.trim());
      setInput('');
    }
  };

  const formatTime = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString([], { 
      hour: '2-digit', 
      minute: '2-digit' 
    });
  };

  const truncateId = (id: string) => id.slice(0, 8);

  const getStatusColor = () => {
    switch (status) {
      case 'connected': return 'bg-green-500';
      case 'connecting': return 'bg-yellow-500';
      case 'disconnected': return 'bg-red-500';
    }
  };

  const getStatusText = () => {
    switch (status) {
      case 'connected': return 'Connected';
      case 'connecting': return 'Connecting...';
      case 'disconnected': return 'Disconnected';
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 text-white flex flex-col items-center justify-center p-4">
      {/* Header */}
      <div className="mb-8 text-center">
        <div className="flex items-center justify-center gap-4 mb-4">
          {/* Zig Logo */}
          <svg width="48" height="48" viewBox="0 0 400 400" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M46.8906 312.749L186.199 131.182H83.7817L68.0608 80.7891H279.186L272.214 93.1973L139.81 265.73H247.209L262.93 316.123H46.1289L46.8906 312.749Z" fill="#F7A41D"/>
            <path d="M318.965 80.7891L305.756 316.123H256.187L271.107 80.7891H318.965Z" fill="#F7A41D"/>
            <path d="M256.187 316.123L271.107 80.7891H318.965L323.447 316.123H256.187Z" fill="#F7A41D"/>
          </svg>
          <span className="text-3xl text-gray-500">+</span>
          {/* Cloudflare Logo */}
          <svg width="48" height="48" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M43.8 41.9c.3-.9.2-1.8-.2-2.5-.4-.6-1.1-1-1.9-1.1l-19.3-.3c-.2 0-.3-.1-.4-.2-.1-.1-.1-.3 0-.4.1-.2.3-.4.5-.4l19.5-.3c2.1-.1 4.3-1.8 5.1-3.9l1-2.8c.1-.2.1-.4 0-.6-1.3-5.9-6.5-10.3-12.8-10.3-5.7 0-10.5 3.6-12.4 8.6-.9-.7-2.1-1-3.3-.9-2.2.3-4 2-4.3 4.2-.1.6-.1 1.2 0 1.7-4.1.3-7.3 3.7-7.3 7.9 0 .4 0 .9.1 1.3 0 .2.2.4.4.4h34.4c.3 0 .5-.2.6-.4l.3-1Z" fill="#F6821F"/>
            <path d="M49.8 28.5h-.5c-.2 0-.3.1-.4.3l-.7 2.4c-.3.9-.2 1.8.2 2.5.4.6 1.1 1 1.9 1.1l3.1.2c.2 0 .3.1.4.2.1.1.1.3 0 .4-.1.2-.3.4-.5.4l-3.3.2c-2.1.1-4.3 1.8-5.1 3.9l-.3.8c-.1.2 0 .3.2.3h13.1c.2 0 .4-.1.4-.3.3-1 .5-2.1.5-3.2 0-5-4.1-9.2-9-9.2Z" fill="#FAAD3F"/>
          </svg>
        </div>
        <h1 className="text-2xl font-bold mb-2">cf-workerz WebSocket Chat</h1>
        <p className="text-gray-400 text-sm max-w-md">
          Real-time chat powered by <span className="text-orange-400">cf-workerz</span> (Zig) 
          with Cloudflare Workers WebSocket API and Durable Objects
        </p>
      </div>

      {/* Chat Container */}
      <div className="w-full max-w-2xl bg-gray-800 rounded-lg shadow-xl overflow-hidden">
        {/* Chat Header */}
        <div className="flex items-center justify-between px-4 py-3 bg-gray-700 border-b border-gray-600">
          <h2 className="font-semibold">Chat</h2>
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${getStatusColor()}`} />
            <span className="text-sm text-gray-300">{getStatusText()}</span>
          </div>
        </div>

        {/* Messages Area */}
        <div className="h-[500px] overflow-y-auto p-4 space-y-3">
          {messages.length === 0 && (
            <div className="text-center text-gray-500 py-8">
              No messages yet. Start the conversation!
            </div>
          )}
          
          {messages.map((msg, index) => {
            if (isSystemMessage(msg)) {
              return (
                <div key={index} className="text-center">
                  <span className="text-gray-500 text-sm italic">
                    {msg.message}
                  </span>
                </div>
              );
            }

            const isCurrentUser = msg.userId === currentUserId;
            
            return (
              <div
                key={index}
                className={`flex flex-col ${isCurrentUser ? 'items-end' : 'items-start'}`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs text-gray-500">
                    {isCurrentUser ? 'You' : truncateId(msg.userId)}
                  </span>
                  <span className="text-xs text-gray-600">
                    {formatTime(msg.timestamp)}
                  </span>
                </div>
                <div
                  className={`max-w-[80%] px-4 py-2 rounded-2xl ${
                    isCurrentUser
                      ? 'bg-blue-600 text-white rounded-br-md'
                      : 'bg-gray-700 text-gray-100 rounded-bl-md'
                  }`}
                >
                  {msg.message}
                </div>
              </div>
            );
          })}
          <div ref={messagesEndRef} />
        </div>

        {/* Input Area */}
        <form onSubmit={handleSubmit} className="p-4 bg-gray-700 border-t border-gray-600">
          <div className="flex gap-2">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder={status === 'connected' ? 'Type a message...' : 'Connecting...'}
              disabled={status !== 'connected'}
              className="flex-1 px-4 py-2 bg-gray-600 text-white placeholder-gray-400 rounded-lg 
                         focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={status !== 'connected' || !input.trim()}
              className="px-6 py-2 bg-blue-600 text-white font-medium rounded-lg 
                         hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500
                         disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Send
            </button>
          </div>
        </form>
      </div>

      {/* Footer */}
      <div className="mt-6 text-center text-gray-500 text-sm">
        <p>
          Your ID: <code className="bg-gray-800 px-2 py-1 rounded">{truncateId(currentUserId)}</code>
        </p>
        <p className="mt-2">
          <a 
            href="https://github.com/user/cf-workerz" 
            className="text-blue-400 hover:underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            View on GitHub
          </a>
        </p>
      </div>
    </div>
  );
}

export default App;
