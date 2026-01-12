import { useState, useEffect, useCallback, useRef } from 'react';

type ChatMessage = {
  userId: string;
  message: string;
  timestamp: number;
}

type SystemMessage = {
  type: 'system';
  message: string;
  timestamp: number;
}

type Message = ChatMessage | SystemMessage;

function isSystemMessage(msg: Message): msg is SystemMessage {
  return 'type' in msg && msg.type === 'system';
}

export function useChat(url: string) {
  const wsRef = useRef<WebSocket | null>(null);
  const [status, setStatus] = useState<'connecting' | 'connected' | 'disconnected'>('connecting');
  const [messages, setMessages] = useState<Message[]>([]);
  const currentUserId = useRef(crypto.randomUUID());
  const reconnectAttempts = useRef(0);

  const connect = useCallback(() => {
    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        setStatus('connected');
        reconnectAttempts.current = 0;
        
        // Send userId when connection opens
        ws.send(JSON.stringify({
          type: 'init',
          userId: currentUserId.current
        }));
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          switch (data.type) {
            case 'history':
              {
                const parsedMessages = data.messages as ChatMessage[];
                setMessages(parsedMessages);
                break;
              }
            case 'system':
              setMessages(prev => [...prev, data as SystemMessage]);
              break;
            default:
              setMessages(prevMessages => {
                const exists = prevMessages.some(msg => 
                  !isSystemMessage(msg) && 
                  msg.timestamp === data.timestamp && 
                  msg.userId === data.userId
                );
                return exists ? prevMessages : [...prevMessages, data as ChatMessage];
              });
          }
        } catch (e) {
          console.error('Failed to parse message:', e);
        }
      };

      ws.onclose = () => {
        setStatus('disconnected');
        // Exponential backoff for reconnection
        const delay = Math.min(1000 * Math.pow(2, reconnectAttempts.current), 30000);
        reconnectAttempts.current++;
        setTimeout(connect, delay);
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
      };

      return () => ws.close();
    } catch (error) {
      console.error('Failed to connect:', error);
      setStatus('disconnected');
      return () => {};
    }
  }, [url]);

  useEffect(() => {
    const cleanup = connect();
    return () => {
      cleanup();
      setMessages([]);
    };
  }, [connect]);

  const sendMessage = useCallback((message: string) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: 'message',
        content: message
      }));
    }
  }, []);

  return {
    messages,
    status,
    sendMessage,
    currentUserId: currentUserId.current,
    isSystemMessage
  };
}
