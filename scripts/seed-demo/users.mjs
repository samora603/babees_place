/**
 * Demo auth users — fictional Kenyan names for portfolio demos.
 * Passwords are for demo only; change in any shared environment.
 */

export const DEMO_ADMIN = {
  email: 'admin@babeesplace.com',
  password: 'Admin123!',
  fullName: 'Amina Otieno',
  phone: '+254712345001',
  role: 'admin',
};

export const DEMO_CUSTOMERS = [
  {
    email: 'customer@babeesplace.com',
    password: 'Customer123!',
    fullName: 'Brian Mwangi',
    phone: '+254722111001',
    role: 'customer',
  },
  {
    email: 'wangechi.njeri@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'Wangechi Njeri',
    phone: '+254733222002',
    role: 'customer',
  },
  {
    email: 'kevin.ochieng@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'Kevin Ochieng',
    phone: '+254700333003',
    role: 'customer',
  },
  {
    email: 'faith.wambui@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'Faith Wambui',
    phone: '+254711444004',
    role: 'customer',
  },
  {
    email: 'daniel.kiprop@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'Daniel Kiprop',
    phone: '+254722555005',
    role: 'customer',
  },
  {
    email: 'mercy.akinyi@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'Mercy Akinyi',
    phone: '+254733666006',
    role: 'customer',
  },
  {
    email: 'james.mutiso@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'James Mutiso',
    phone: '+254700777007',
    role: 'customer',
  },
  {
    email: 'lucy.cherono@babeesplace.demo',
    password: 'DemoUser123!',
    fullName: 'Lucy Cherono',
    phone: '+254711888008',
    role: 'customer',
  },
];

export const ALL_DEMO_USERS = [DEMO_ADMIN, ...DEMO_CUSTOMERS];

/** Sample Nairobi-area addresses keyed by customer email */
export const ADDRESSES_BY_EMAIL = {
  'customer@babeesplace.com': [
    {
      id: 'a4000000-0000-4000-8000-000000000001',
      label: 'home',
      recipient_name: 'Brian Mwangi',
      phone: '+254722111001',
      county: 'Nairobi',
      town: 'Kilimani',
      street_address: 'Argwings Kodhek Rd, Court 12 Apt B3',
      additional_directions: 'Gate code 4412',
      is_default: true,
    },
  ],
  'wangechi.njeri@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000002',
      label: 'home',
      recipient_name: 'Wangechi Njeri',
      phone: '+254733222002',
      county: 'Nairobi',
      town: 'South B',
      street_address: 'Mukoma Road, House 7',
      additional_directions: null,
      is_default: true,
    },
    {
      id: 'a4000000-0000-4000-8000-000000000003',
      label: 'work',
      recipient_name: 'Wangechi Njeri',
      phone: '+254733222002',
      county: 'Nairobi',
      town: 'Upper Hill',
      street_address: 'Hospital Road, Suite 4',
      additional_directions: 'Reception will hold packages',
      is_default: false,
    },
  ],
  'kevin.ochieng@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000004',
      label: 'home',
      recipient_name: 'Kevin Ochieng',
      phone: '+254700333003',
      county: 'Kiambu',
      town: 'Ruiru',
      street_address: 'Eastern Bypass, Greenview Estate Block C',
      additional_directions: 'Ask for plot 18',
      is_default: true,
    },
  ],
  'faith.wambui@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000005',
      label: 'home',
      recipient_name: 'Faith Wambui',
      phone: '+254711444004',
      county: 'Nairobi',
      town: 'Westlands',
      street_address: 'Ring Road Parklands, Flat 9A',
      additional_directions: null,
      is_default: true,
    },
  ],
  'daniel.kiprop@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000006',
      label: 'home',
      recipient_name: 'Daniel Kiprop',
      phone: '+254722555005',
      county: 'Nairobi',
      town: 'Lavington',
      street_address: 'James Gichuru Road, Villa 3',
      additional_directions: 'Security will call',
      is_default: true,
    },
  ],
  'mercy.akinyi@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000007',
      label: 'home',
      recipient_name: 'Mercy Akinyi',
      phone: '+254733666006',
      county: 'Kajiado',
      town: 'Kitengela',
      street_address: 'Namanga Road, Acacia Courts',
      additional_directions: 'Unit 22',
      is_default: true,
    },
  ],
  'james.mutiso@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000008',
      label: 'other',
      recipient_name: 'James Mutiso',
      phone: '+254700777007',
      county: 'Nairobi',
      town: 'Eastleigh',
      street_address: '1st Avenue, Shopfront collection',
      additional_directions: 'Prefer evening delivery',
      is_default: true,
    },
  ],
  'lucy.cherono@babeesplace.demo': [
    {
      id: 'a4000000-0000-4000-8000-000000000009',
      label: 'home',
      recipient_name: 'Lucy Cherono',
      phone: '+254711888008',
      county: 'Nairobi',
      town: 'Karen',
      street_address: 'Bogani Road, Cottage 5',
      additional_directions: null,
      is_default: true,
    },
  ],
};
