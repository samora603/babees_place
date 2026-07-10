import React from 'react';

const Skeleton = ({ className = '', variant = 'rectangular', ...props }) => {
  const baseClasses = 'animate-pulse bg-white/5 border border-white/5';
  
  const variants = {
    rectangular: 'rounded-xl',
    circular: 'rounded-full',
    text: 'rounded-md h-4 w-full',
  };

  return (
    <div 
      className={`${baseClasses} ${variants[variant]} ${className}`} 
      {...props}
    />
  );
};

export default Skeleton;
