import { Component } from 'react';
import { reportError } from '@/services/errorReportingService';

/**
 * React error boundary — catches render errors in the subtree.
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, message: '' };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, message: error?.message || 'Something went wrong' };
  }

  componentDidCatch(error, info) {
    reportError(error, 'react.error_boundary', {
      componentStack: info?.componentStack?.slice?.(0, 1000),
    });
  }

  handleRetry = () => {
    this.setState({ hasError: false, message: '' });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;
      return (
        <div
          className="min-h-[40vh] flex flex-col items-center justify-center p-8 text-center"
          role="alert"
        >
          <h1 className="font-display text-2xl text-white mb-2">Something went wrong</h1>
          <p className="text-slate-400 text-sm mb-6 max-w-md">{this.state.message}</p>
          <button type="button" className="btn-primary" onClick={this.handleRetry}>
            Try again
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
