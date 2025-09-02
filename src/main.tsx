import React, { Suspense } from "react";
import { createRoot } from 'react-dom/client';
import App from './App.tsx';
import { LoadingSpinner } from "@/components/ui/loading-spinner";
import './index.css';

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Suspense fallback={
      <div className="min-h-screen bg-background flex items-center justify-center">
        <LoadingSpinner size="lg" />
      </div>
    }>
      <App />
    </Suspense>
  </React.StrictMode>
);
