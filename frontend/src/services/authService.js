import { supabase } from "@/lib/supabaseClient";

export const authService = {
async requestOTP(phoneOrEmail) {
const isEmail = phoneOrEmail.includes("@");

```
if (isEmail) {
  return await supabase.auth.signInWithOtp({
    email: phoneOrEmail,
  });
}

return await supabase.auth.signInWithOtp({
  phone: phoneOrEmail,
});
```

},

async verifyOTP(phoneOrEmail, token) {
const isEmail = phoneOrEmail.includes("@");

```
if (isEmail) {
  return await supabase.auth.verifyOtp({
    email: phoneOrEmail,
    token,
    type: "email",
  });
}

return await supabase.auth.verifyOtp({
  phone: phoneOrEmail,
  token,
  type: "sms",
});
```

},

async adminLogin(email, password) {
return await supabase.auth.signInWithPassword({
email,
password,
});
},

async refreshToken() {
return await supabase.auth.refreshSession();
},

async logout() {
return await supabase.auth.signOut();
},

async getMe() {
const { data, error } = await supabase.auth.getUser();

```
if (error) {
  return {
    data: null,
    error,
  };
}

return {
  data: data.user,
  error: null,
};
```

},

async getSession() {
return await supabase.auth.getSession();
},
};
