import { useState, useRef, useEffect } from 'react';
import clsx from 'clsx';

export default function OtpInput({ length = 6, value, onChange, className }) {
  const [otp, setOtp] = useState(new Array(length).fill(''));
  const inputRefs = useRef([]);

  useEffect(() => {
    if (value) {
      setOtp(value.split('').slice(0, length));
    }
  }, [value, length]);

  const handleChange = (e, index) => {
    let { value: inputValue } = e.target;
    // Allow only numbers
    inputValue = inputValue.replace(/[^0-9]/g, '');
    
    if (!inputValue) return;
    
    const newOtp = [...otp];
    // If user pastes a string, take the first char for this box
    newOtp[index] = inputValue.charAt(inputValue.length - 1);
    setOtp(newOtp);
    onChange(newOtp.join(''));

    // Move to next input
    if (index < length - 1 && inputValue) {
      inputRefs.current[index + 1].focus();
    }
  };

  const handleKeyDown = (e, index) => {
    if (e.key === 'Backspace') {
      const newOtp = [...otp];
      if (newOtp[index]) {
         newOtp[index] = '';
         setOtp(newOtp);
         onChange(newOtp.join(''));
      } else if (index > 0) {
        // Move to prev input
        inputRefs.current[index - 1].focus();
      }
    } else if (e.key === 'ArrowLeft' && index > 0) {
      inputRefs.current[index - 1].focus();
    } else if (e.key === 'ArrowRight' && index < length - 1) {
      inputRefs.current[index + 1].focus();
    }
  };

  const handlePaste = (e) => {
    e.preventDefault();
    const pastedData = e.clipboardData.getData('text').replace(/[^0-9]/g, '').slice(0, length);
    if (!pastedData) return;
    
    const newOtp = [...otp];
    pastedData.split('').forEach((char, i) => {
      newOtp[i] = char;
    });
    setOtp(newOtp);
    onChange(newOtp.join(''));
    
    // Focus last filled box
    const focusIndex = Math.min(pastedData.length, length - 1);
    inputRefs.current[focusIndex].focus();
  };

  return (
    <div className={clsx("flex justify-center gap-2 sm:gap-3", className)}>
      {otp.map((data, index) => (
        <input
          key={index}
          type="text"
          inputMode="numeric"
          maxLength={1}
          ref={(el) => (inputRefs.current[index] = el)}
          value={data}
          onChange={(e) => handleChange(e, index)}
          onKeyDown={(e) => handleKeyDown(e, index)}
          onPaste={handlePaste}
          className="w-10 h-12 sm:w-12 sm:h-14 bg-white/5 border border-white/10 rounded-xl text-center text-xl sm:text-2xl font-bold text-white shadow-inner focus:border-brand-500 focus:ring-2 focus:ring-brand-500/50 outline-none transition-all duration-200"
        />
      ))}
    </div>
  );
}
