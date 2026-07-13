import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';

import App from './App';
import './index.css';

import { AuthProvider } from './context/AuthContext';
import { CartProvider } from './context/CartContext';
import { WishlistProvider } from './context/WishlistContext';
import ErrorBoundary from './components/ErrorBoundary';
import { errorReportingService } from './services/errorReportingService';
import { logger } from './services/logger';
import { registerServiceWorker } from './pwa/registerServiceWorker';
import { validateClientEnv } from './utils/envValidation';

errorReportingService.installGlobalErrorHandlers();
const envCheck = validateClientEnv();
if (!envCheck.ok) {
  logger.warn('app', 'Client env incomplete', envCheck);
}
envCheck.warnings.forEach((w) => logger.error('app', w));
logger.info('app', 'Babees Place bootstrapping', { mode: import.meta.env.MODE });
registerServiceWorker();

ReactDOM.createRoot(document.getElementById('root')).render(
  <ErrorBoundary>
    <BrowserRouter>
      <AuthProvider>
        <CartProvider>
          <WishlistProvider>
            <App />
            <Toaster
              position="top-right"
              toastOptions={{
                duration: 3000,
                style: {
                  background: '#111',
                  color: '#f1f5f9',
                  border: '1px solid rgba(212,175,55,0.25)',
                },
                success: {
                  iconTheme: { primary: '#D4AF37', secondary: '#111' },
                },
                error: {
                  iconTheme: { primary: '#f87171', secondary: '#111' },
                },
              }}
            />
          </WishlistProvider>
        </CartProvider>
      </AuthProvider>
    </BrowserRouter>
  </ErrorBoundary>,
);
