"use client";

import { User, Bot } from "lucide-react";

export function ChatBubble({ message, isUser }: { message: string; isUser: boolean }) {
  return (
    <div className={`flex gap-3 ${isUser ? "flex-row-reverse" : ""}`}>
      <div className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
        isUser ? "bg-gray-200" : "bg-primary text-white"
      }`}>
        {isUser ? <User size={16} /> : <Bot size={16} />}
      </div>
      <div className={`max-w-[80%] p-4 rounded-2xl ${
        isUser 
          ? "bg-primary text-white rounded-tr-sm" 
          : "bg-white border rounded-tl-sm"
      }`}>
        <p className="text-sm leading-relaxed whitespace-pre-wrap">{message}</p>
      </div>
    </div>
  );
}
