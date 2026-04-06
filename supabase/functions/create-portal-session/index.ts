import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Stripe from 'https://esm.sh/stripe@12.0.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') as string, {
  apiVersion: '2022-11-15',
  httpClient: Stripe.createFetchHttpClient(),
})

const corsHeaders = { 
  'Access-Control-Allow-Origin': '*', 
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' 
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { customerId, returnUrl, newPriceId } = await req.json()

    let portalOptions: any = {
      customer: customerId,
      return_url: returnUrl,
    }

    // Se o usuário quer mudar de plano (Upgrade Flow)
    if (newPriceId) {
      const subs = await stripe.subscriptions.list({ customer: customerId, status: 'active', limit: 1 })
      if (subs.data.length > 0) {
        portalOptions.flow_data = {
          type: 'subscription_update',
          subscription_update: { subscription: subs.data[0].id }
        }
      }
    }

    const session = await stripe.billingPortal.sessions.create(portalOptions)
    return new Response(JSON.stringify({ url: session.url }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
  }
})
