import { Link } from 'react-router-dom';
import { FiArrowRight } from 'react-icons/fi';
import { FaInstagram, FaTiktok, FaWhatsapp } from 'react-icons/fa';

import { Swiper, SwiperSlide } from 'swiper/react';
import { Autoplay, EffectFade, Pagination } from 'swiper/modules';

import 'swiper/css';
import 'swiper/css/effect-fade';
import 'swiper/css/pagination';

export default function Hero() {

  const heroImages = [
    '/hero_carousel/hero1.jpeg',
    '/hero_carousel/hero2.jpeg',
    '/hero_carousel/hero3.jpeg',
    '/hero_carousel/hero4.jpeg',
    '/hero_carousel/hero5.jpeg',
    '/hero_carousel/hero6.jpeg',
  ];

  return (
    <section className="relative min-h-[90vh] flex items-center justify-center overflow-hidden">

      {/* ===================== */}
      {/* BACKGROUND CAROUSEL */}
      {/* ===================== */}
      <div className="absolute inset-0 z-0">

        <Swiper
          modules={[Autoplay, EffectFade, Pagination]}
          effect="fade"
          loop={true}
          speed={1500}
          autoplay={{
            delay: 5000,
            disableOnInteraction: false,
          }}
          pagination={{ clickable: true }}
          className="h-full w-full"
        >
          {heroImages.map((image, index) => (
            <SwiperSlide key={index}>
              <div
                className="h-full w-full bg-cover bg-center animate-slow-zoom"
                style={{
                  backgroundImage: `url(${image})`,
                  backgroundPosition: 'center',
                  backgroundSize: '108%',
                  filter: 'contrast(1.05) saturate(1.1)',
                }}
              >

                {/* CLEANER OVERLAY (FIXED BLUR ISSUE) */}
                <div className="absolute inset-0 bg-black/35"></div>

                {/* LIGHT GRADIENT FOR DEPTH */}
                <div className="absolute inset-0 bg-gradient-to-b from-black/30 via-transparent to-black/70"></div>

                {/* SUBTLE GOLD GLOW (NOT TOO STRONG) */}
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(212,175,55,0.08),transparent_65%)]"></div>

              </div>
            </SwiperSlide>
          ))}
        </Swiper>
      </div>

      {/* ===================== */}
      {/* CONTENT */}
      {/* ===================== */}
      <div className="section-container relative z-10 text-center px-4 py-32 md:py-48">

        <h1 className="font-display font-extrabold text-5xl md:text-8xl text-white mb-6 leading-tight tracking-tight drop-shadow-xl">
          Collective <span className="text-brand-500">Luxury</span> Outfits
        </h1>

        <p className="text-slate-100 text-lg md:text-2xl max-w-3xl mx-auto mb-4 font-medium leading-relaxed">
          Shop at your own comfort, from your own comfort.
          <span className="text-brand-500 italic"> Bee you.</span>
          {' '}Curated elegance.
          <span className="text-brand-500 italic"> Exclusively yours.</span>
        </p>

        <p className="text-slate-300 text-md md:text-lg max-w-2xl mx-auto mb-8 italic opacity-90">
          Swipe to thrift and complete acquisition seamlessly through M-Pesa.
        </p>

        {/* DELIVERY BADGE */}
        <div className="inline-block bg-brand-500/10 border border-brand-500/30 px-6 py-3 rounded-xl mb-12 backdrop-blur-md">
          <p className="text-brand-500 text-sm md:text-base font-semibold">
            Free same-day delivery from Roysambu to Juja (within 24 hours)
          </p>
        </div>

        {/* CTA */}
        <div className="flex flex-col sm:flex-row gap-6 justify-center items-center mb-12">

          <Link
            to="/shop"
            className="group relative bg-brand-500 text-black font-bold py-4 px-10 rounded-full hover:bg-brand-400 transition-all duration-300 overflow-hidden"
          >
            <span className="relative z-10 flex items-center gap-2 uppercase tracking-widest text-sm">
              Start Shopping <FiArrowRight className="group-hover:translate-x-1 transition-transform" />
            </span>
          </Link>

          <a
            href="https://wa.me/254785098972"
            target="_blank"
            rel="noopener noreferrer"
            className="border-2 border-brand-500 text-brand-500 font-bold py-4 px-10 rounded-full hover:bg-brand-500/10 transition-all duration-300 uppercase tracking-widest text-sm"
          >
            Chat on WhatsApp
          </a>

        </div>

        {/* SOCIALS */}
        <div className="flex justify-center gap-8">

          {[
            { icon: FaInstagram, link: 'https://instagram.com/Babis-Place' },
            { icon: FaTiktok, link: 'https://tiktok.com/@babiigatyou' },
            { icon: FaWhatsapp, link: 'https://wa.me/254785098972' }
          ].map((social, i) => (
            <a
              key={i}
              href={social.link}
              target="_blank"
              rel="noopener noreferrer"
              className="text-brand-500/70 hover:text-brand-500 hover:scale-125 transition-all"
            >
              <social.icon size={24} />
            </a>
          ))}

        </div>

      </div>

      {/* bottom fade */}
      <div className="absolute bottom-0 left-0 w-full h-24 bg-gradient-to-t from-black to-transparent z-10"></div>

    </section>
  );
}