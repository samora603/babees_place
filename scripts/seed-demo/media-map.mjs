/**
 * Curated demo media for Babees Place storefront.
 * Absolute Unsplash CDN URLs (w/ responsive query params). No schema changes.
 *
 * images[] shape: { url, path, isPrimary, alt, role?: 'primary'|'gallery'|'thumb' }
 */

const U = (photoId, w = 1200) =>
  `https://images.unsplash.com/${photoId}?auto=format&fit=crop&w=${w}&q=80`;

function gallery(slug, name, photos) {
  const [primary, ...rest] = photos;
  const images = [
    {
      url: U(primary, 1200),
      path: `media/products/${slug}/01.jpg`,
      isPrimary: true,
      alt: `${name} — primary product photo`,
      role: 'primary',
    },
    ...rest.slice(0, 2).map((id, i) => ({
      url: U(id, 1000),
      path: `media/products/${slug}/0${i + 2}.jpg`,
      isPrimary: false,
      alt: `${name} — gallery view ${i + 2}`,
      role: 'gallery',
    })),
  ];
  // Dedicated thumb = primary at card-friendly width (same asset, transform via w=)
  const thumb = U(primary, 600);
  images.push({
    url: thumb,
    path: `media/products/${slug}/thumb.jpg`,
    isPrimary: false,
    alt: `${name} — thumbnail`,
    role: 'thumb',
  });
  return {
    image_url: images[0].url,
    images,
    thumb_url: thumb,
  };
}

/**
 * Merchandising visual groups (Sprint 3 plan) → product slugs.
 * Store DB categories remain Fashion / Electronics / Home / Toys / Beauty.
 */
export const VISUAL_CATEGORIES = {
  sneakers: {
    label: 'Sneakers',
    banner: 'category_banners/sneakers.jpg',
    slugs: ['bp-fsh-011', 'bp-fsh-012'],
  },
  'casual-shoes': {
    label: 'Casual Shoes',
    banner: 'category_banners/casual-shoes.jpg',
    slugs: ['bp-fsh-013'],
  },
  hoodies: {
    label: 'Hoodies',
    banner: 'category_banners/hoodies.jpg',
    slugs: ['bp-fsh-003', 'bp-fsh-004'],
  },
  't-shirts': {
    label: 'T-Shirts',
    banner: 'category_banners/t-shirts.jpg',
    slugs: ['bp-fsh-001', 'bp-fsh-002'],
  },
  accessories: {
    label: 'Accessories',
    banner: 'category_banners/accessories.jpg',
    slugs: [
      'bp-fsh-014',
      'bp-fsh-015',
      'bp-bty-044',
      'bp-bty-045',
      'bp-bty-046',
      'bp-bty-050',
    ],
  },
  toys: {
    label: 'Toys',
    banner: 'category_banners/toys.jpg',
    slugs: [
      'bp-toy-036',
      'bp-toy-037',
      'bp-toy-038',
      'bp-toy-039',
      'bp-toy-040',
      'bp-toy-041',
      'bp-toy-042',
      'bp-toy-043',
    ],
  },
  'home-essentials': {
    label: 'Home Essentials',
    banner: 'category_banners/home-essentials.jpg',
    slugs: [
      'bp-hom-026',
      'bp-hom-027',
      'bp-hom-028',
      'bp-hom-029',
      'bp-hom-030',
      'bp-hom-031',
      'bp-hom-032',
      'bp-hom-033',
      'bp-hom-034',
      'bp-hom-035',
    ],
  },
};

/** Store category banners (match live categories.slug) — 16:9 */
export const CATEGORY_BANNERS = {
  fashion: {
    file: 'category_banners/fashion.jpg',
    url: '/category_banners/fashion.jpg',
    alt: 'Fashion — apparel and footwear',
    aspect: '16:9',
  },
  electronics: {
    file: 'category_banners/electronics.jpg',
    url: '/category_banners/electronics.jpg',
    alt: 'Electronics — gadgets and tech',
    aspect: '16:9',
  },
  'home-living': {
    file: 'category_banners/home-living.jpg',
    url: '/category_banners/home-living.jpg',
    alt: 'Home & Living — essentials for every room',
    aspect: '16:9',
  },
  'toys-kids': {
    file: 'category_banners/toys-kids.jpg',
    url: '/category_banners/toys-kids.jpg',
    alt: 'Toys & Kids — play and learning',
    aspect: '16:9',
  },
  'beauty-accessories': {
    file: 'category_banners/beauty-accessories.jpg',
    url: '/category_banners/beauty-accessories.jpg',
    alt: 'Beauty & Accessories — bags, care, and style',
    aspect: '16:9',
  },
};

/** Homepage hero carousel (public paths) */
export const HERO_ASSETS = [
  { src: '/hero_carousel/hero1.jpeg', alt: 'Babees Place lifestyle look 1' },
  { src: '/hero_carousel/hero2.jpeg', alt: 'Babees Place lifestyle look 2' },
  { src: '/hero_carousel/hero3.jpeg', alt: 'Babees Place lifestyle look 3' },
  { src: '/hero_carousel/hero4.jpeg', alt: 'Babees Place lifestyle look 4' },
  { src: '/hero_carousel/hero5.jpeg', alt: 'Babees Place lifestyle look 5' },
  { src: '/hero_carousel/hero6.jpeg', alt: 'Babees Place lifestyle look 6' },
];

/**
 * Featured / homepage visual priority (strong product shots).
 * Does not change business rules — documentation + apply script may soft-check.
 */
export const HOMEPAGE_FEATURED_SLUGS = [
  'bp-fsh-001', // tee white
  'bp-fsh-003', // hoodie charcoal
  'bp-fsh-005', // bomber
  'bp-fsh-009', // dress sand
  'bp-fsh-011', // sneakers white
  'bp-elc-016', // earbuds
  'bp-elc-017', // speaker
  'bp-elc-020', // watch
];

/** slug → Unsplash photo IDs [primary, gallery2, gallery3] */
const PHOTOS = {
  // Fashion
  'bp-fsh-001': ['photo-1521572163474-6864f9cf17ab', 'photo-1583743814966-8936f5b7be1a', 'photo-1562157873-818bc0726f68'],
  'bp-fsh-002': ['photo-1576566588028-4147f3842f27', 'photo-1503342217505-b0a15ec3261c', 'photo-1529374255404-311a2a4f1fd9'],
  'bp-fsh-003': ['photo-1556821840-3a63f95609a7', 'photo-1578768079052-aa76e52ff62e', 'photo-1620799140408-edc6dcb6d633'],
  'bp-fsh-004': ['photo-1620799140188-3b2a02fd9a77', 'photo-1556821840-3a63f95609a7', 'photo-1618354691373-d851c5c3a990'],
  'bp-fsh-005': ['photo-1591047139829-d91aecb6caea', 'photo-1548126032-079a0fb0099d', 'photo-1495105787522-5334e3ffa0ef'],
  'bp-fsh-006': ['photo-1576995853123-5a10305d93c0', 'photo-1551028719-00167b16eac5', 'photo-1601333144130-8cbb312386b6'],
  'bp-fsh-007': ['photo-1542272604-787c3835535d', 'photo-1604176354204-9268737828e4', 'photo-1582418702059-97ebafb35d09'],
  'bp-fsh-008': ['photo-1475178626620-a4d074967337', 'photo-1541099649105-f69ad21f3246', 'photo-1542272604-787c3835535d'],
  'bp-fsh-009': ['photo-1595777457583-95e059d581b8', 'photo-1515372039744-b8f02a3ae446', 'photo-1496747611176-843222e1e57c'],
  'bp-fsh-010': ['photo-1572804013309-59a88b7e92f1', 'photo-1585487000160-6ebcfceb0d03', 'photo-1594633312681-425c7b97ccd1'],
  'bp-fsh-011': ['photo-1542291026-7eec264c27ff', 'photo-1606107557195-0e29a4b5b4aa', 'photo-1460353581641-37baddab0fa2'],
  'bp-fsh-012': ['photo-1600185365483-26d7a4cc7519', 'photo-1595950653106-6c9ebd614d3a', 'photo-1549298916-b41d501d3772'],
  'bp-fsh-013': ['photo-1603487742131-4160ec999306', 'photo-1562273138-f46be4ebdf33', 'photo-1603808033192-082d59554583'],
  'bp-fsh-014': ['photo-1548036328-c9fa89d128fa', 'photo-1590874103328-eac38a683ce0', 'photo-1553062407-98eeb64c6a62'],
  'bp-fsh-015': ['photo-1588850561407-ed78c282e89b', 'photo-1521369909029-2afed882baee', 'photo-1575428652377-a2d80e2277b0'],
  // Electronics
  'bp-elc-016': ['photo-1590658268037-6bf12165a8df', 'photo-1606220945770-b5b6c2c55bf1', 'photo-1618366712010-f4ae9c647dcb'],
  'bp-elc-017': ['photo-1608043152269-423dbba4e7e1', 'photo-1545454675-3531b543be5d', 'photo-1589003077984-894e133dabab'],
  'bp-elc-018': ['photo-1609091839311-b9b6d73f2f4d', 'photo-1625794084867-8ddd23996b58', 'photo-1583863788434-e58a36330cf0'],
  'bp-elc-019': ['photo-1583863788434-e58a36330cf0', 'photo-1625948515291-69613efd103f', 'photo-1609091839311-b9b6d73f2f4d'],
  'bp-elc-020': ['photo-1579586337278-3befd40fd17a', 'photo-1434494878577-86c23bcb06b9', 'photo-1523275335684-37898b6baf30'],
  'bp-elc-021': ['photo-1527864550417-7fd91fc51a46', 'photo-1615663245857-ac93bb7c39e7', 'photo-1563297007-0686b7003af7'],
  'bp-elc-022': ['photo-1625948515291-69613efd103f', 'photo-1593640408182-31c70c8268f1', 'photo-1587825140708-dfaf72ae4b04'],
  'bp-elc-023': ['photo-1527864550417-7fd91fc51a46', 'photo-1496181133206-80ce9b88a853', 'photo-1587825140708-dfaf72ae4b04'],
  'bp-elc-024': ['photo-1558618666-fcd25c85cd64', 'photo-1505740420928-5e560c06d30e', 'photo-1513506003901-1e6a229e2d15'],
  'bp-elc-025': ['photo-1507473885765-e6ed057f782c', 'photo-1513506003901-1e6a229e2d15', 'photo-1534073828943-f801091bb18c'],
  // Home
  'bp-hom-026': ['photo-1616046220798-a697b87c2b0c', 'photo-1586023492125-27b2c045efd7', 'photo-1555041469-a586c61ea9bc'],
  'bp-hom-027': ['photo-1584100936595-c0654b55a2e2', 'photo-1631889993959-41b4e9c6e3c5', 'photo-1616486338812-3dadae4b4ace'],
  'bp-hom-028': ['photo-1563861826100-9cb668332e1b', 'photo-1509042239860-f550ce710b93', 'photo-1493663284031-b7e3aefcae8e'],
  'bp-hom-029': ['photo-1582735689369-4fe89db7114c', 'photo-1556911220-bff31c875d1f', 'photo-1581578731548-c64695cc6952'],
  'bp-hom-030': ['photo-1514228742587-6b1558fcc36f', 'photo-1495474472287-4d71bcdd2085', 'photo-1577937928226-c0c6a1c6b4e1'],
  'bp-hom-031': ['photo-1556911220-bff31c875d1f', 'photo-1581578731548-c64695cc6952', 'photo-1600585154340-be6161a56a0c'],
  'bp-hom-032': ['photo-1522771739844-6a9f6d5f14af', 'photo-1631049307264-da0ec9d70304', 'photo-1616594039964-ae9021a400a0'],
  'bp-hom-033': ['photo-1602143407151-7111542de6e8', 'photo-1523362628745-0c100150b504', 'photo-1602143407151-7111542de6e8'],
  'bp-hom-034': ['photo-1584568694244-14fbdf83bd30', 'photo-1600585154340-be6161a56a0c', 'photo-1556911220-bff31c875d1f'],
  'bp-hom-035': ['photo-1593062096033-9a26b09da705', 'photo-1497366216548-37526070297c', 'photo-1587825140708-dfaf72ae4b04'],
  // Toys
  'bp-toy-036': ['photo-1587654780291-39c9404d746b', 'photo-1566576912321-d58ddd7a6088', 'photo-1596461404969-9ae70f2830c1'],
  'bp-toy-037': ['photo-1559454403-b1fb1002ea1e', 'photo-1530325553241-4f6e9f7a0f1c', 'photo-1566576912321-d58ddd7a6088'],
  'bp-toy-038': ['photo-1558618666-fcd25c85cd64', 'photo-1594787318284-a5e3c0e0b1a0', 'photo-1566576912321-d58ddd7a6088'],
  'bp-toy-039': ['photo-1606092195730-5d7b9af1efc5', 'photo-1515488042361-ee00e0ddd4e4', 'photo-1587654780291-39c9404d746b'],
  'bp-toy-040': ['photo-1515488042361-ee00e0ddd4e4', 'photo-1503454537195-1dcabb73ffb9', 'photo-1587654780291-39c9404d746b'],
  'bp-toy-041': ['photo-1558877385-1c5b0b1c0c5e', 'photo-1566576912321-d58ddd7a6088', 'photo-1596461404969-9ae70f2830c1'],
  'bp-toy-042': ['photo-1519861531473-9200262188bf', 'photo-1574629810360-7efbbe195018', 'photo-1546519638-68e109498ffc'],
  'bp-toy-043': ['photo-1599058917212-d750089bc07e', 'photo-1518611012118-696072aa579a', 'photo-1571019613454-1cb2f99b2d8b'],
  // Beauty & accessories
  'bp-bty-044': ['photo-1553062407-98eeb64c6a62', 'photo-1622560480605-d83c8532435e', 'photo-1590874103328-eac38a683ce0'],
  'bp-bty-045': ['photo-1627123424574-724758594e93', 'photo-1553062407-98eeb64c6a62', 'photo-1601924994987-69e26d50dc26'],
  'bp-bty-046': ['photo-1511499767150-a48a237f0083', 'photo-1572635196237-14b3f281503f', 'photo-1473496169904-658ba7c44d8a'],
  'bp-bty-047': ['photo-1556228578-0d85b1a4d571', 'photo-1570194065650-d99fb4b38b17', 'photo-1598440947619-2c35fc9aa908'],
  'bp-bty-048': ['photo-1535585209827-a15fcdbc4c2d', 'photo-1522338242992-e1a54906a8da', 'photo-1571875257727-256c39da42af'],
  'bp-bty-049': ['photo-1556228720-195a672e8a03', 'photo-1570194065650-d99fb4b38b17', 'photo-1598440947619-2c35fc9aa908'],
  'bp-bty-050': ['photo-1548036328-c9fa89d128fa', 'photo-1553062407-98eeb64c6a62', 'photo-1581605405669-fbf945cd739e'],
};

const NAMES = {
  'bp-fsh-001': 'Essential Cotton Tee — White',
  'bp-fsh-002': 'Graphic Tee — City Lines',
  'bp-fsh-003': 'Fleece Hoodie — Charcoal',
  'bp-fsh-004': 'Zip Hoodie — Olive',
  'bp-fsh-005': 'Light Bomber Jacket — Black',
  'bp-fsh-006': 'Denim Jacket — Classic Blue',
  'bp-fsh-007': 'Slim Fit Jeans — Indigo',
  'bp-fsh-008': 'Straight Jeans — Washed Grey',
  'bp-fsh-009': 'Linen Midi Dress — Sand',
  'bp-fsh-010': 'Shirt Dress — Navy Stripe',
  'bp-fsh-011': 'Urban Runner Sneakers — White',
  'bp-fsh-012': 'Court Sneakers — Black/Gum',
  'bp-fsh-013': 'Leather Slide Sandals — Tan',
  'bp-fsh-014': 'Canvas Crossbody Bag — Khaki',
  'bp-fsh-015': 'Structured Cap — Black',
  'bp-elc-016': 'Wireless Earbuds — Pearl White',
  'bp-elc-017': 'Bluetooth Speaker — Midnight',
  'bp-elc-018': 'Power Bank 20,000 mAh',
  'bp-elc-019': 'USB-C Fast Phone Charger 30W',
  'bp-elc-020': 'Smart Watch — Active Fit',
  'bp-elc-021': 'Wireless Mouse — Graphite',
  'bp-elc-022': 'USB-C Hub 7-in-1',
  'bp-elc-023': 'Aluminium Laptop Stand',
  'bp-elc-024': 'Portable Desk Fan — Mini',
  'bp-elc-025': 'LED Desk Lamp — Warm White',
  'bp-hom-026': 'Woven Storage Basket — Large',
  'bp-hom-027': 'Throw Pillow Cover — Terracotta',
  'bp-hom-028': 'Silent Wall Clock — Oak Frame',
  'bp-hom-029': 'Collapsible Laundry Basket',
  'bp-hom-030': 'Ceramic Coffee Mug Set (4)',
  'bp-hom-031': 'Kitchen Drawer Organizer',
  'bp-hom-032': 'Cotton Bed Sheet Set — Queen',
  'bp-hom-033': 'Insulated Water Bottle 750ml',
  'bp-hom-034': 'Food Storage Containers (6-Pack)',
  'bp-hom-035': 'Desk Organizer Tray',
  'bp-toy-036': 'Wooden Building Blocks (60 pcs)',
  'bp-toy-037': 'Stuffed Bear — Honey',
  'bp-toy-038': 'Remote Control Car — Rally',
  'bp-toy-039': 'Family Puzzle Set — 500 pcs',
  'bp-toy-040': 'Educational Flash Cards',
  'bp-toy-041': 'Play Kitchen Set — Mini Chef',
  'bp-toy-042': 'Junior Basketball Size 5',
  'bp-toy-043': 'Skipping Rope — Adjustable',
  'bp-bty-044': 'Everyday Backpack — Slate',
  'bp-bty-045': 'Leather Wallet — Cognac',
  'bp-bty-046': 'Polarized Sunglasses — Tortoise',
  'bp-bty-047': 'Shea Body Lotion 400ml',
  'bp-bty-048': 'Gentle Care Shampoo 350ml',
  'bp-bty-049': 'Foaming Face Cleanser 150ml',
  'bp-bty-050': 'Weekend Travel Bag — Navy',
};

export const PRODUCT_MEDIA = Object.fromEntries(
  Object.entries(PHOTOS).map(([slug, photos]) => [
    slug,
    gallery(slug, NAMES[slug] || slug, photos),
  ]),
);

export function mediaForSlug(slug, fallbackName = slug) {
  if (PRODUCT_MEDIA[slug]) return PRODUCT_MEDIA[slug];
  // fallback: generic apparel
  return gallery(slug, fallbackName, [
    'photo-1441986300917-64674bd600d8',
    'photo-1472851294608-062f824d29cc',
    'photo-1483985988355-763728e1935b',
  ]);
}

/** Unsplash source URLs used to materialize local category banners (16:9). */
export const CATEGORY_BANNER_SOURCES = {
  fashion: 'https://images.unsplash.com/photo-1445205170230-053b83016050?auto=format&fit=crop&w=1600&h=900&q=80',
  electronics: 'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1600&h=900&q=80',
  'home-living': 'https://images.unsplash.com/photo-1618221195710-dd6b41faaea6?auto=format&fit=crop&w=1600&h=900&q=80',
  'toys-kids': 'https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=1600&h=900&q=80',
  'beauty-accessories': 'https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?auto=format&fit=crop&w=1600&h=900&q=80',
  sneakers: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=1600&h=900&q=80',
  'casual-shoes': 'https://images.unsplash.com/photo-1603487742131-4160ec999306?auto=format&fit=crop&w=1600&h=900&q=80',
  hoodies: 'https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1600&h=900&q=80',
  't-shirts': 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=1600&h=900&q=80',
  accessories: 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=1600&h=900&q=80',
  toys: 'https://images.unsplash.com/photo-1566576912321-d58ddd7a6088?auto=format&fit=crop&w=1600&h=900&q=80',
  'home-essentials': 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=1600&h=900&q=80',
};
