// supabase/functions/stripe-webhook/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Stripe from 'https://esm.sh/stripe@12.0.0?target=deno'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') as string, {
  apiVersion: '2022-11-15',
  httpClient: Stripe.createFetchHttpClient(),
})

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') as string,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') as string
)

serve(async (req) => {
  const signature = req.headers.get('stripe-signature');

  try {
    const body = await req.text();
    const event = stripe.webhooks.constructEvent(
      body,
      signature!,
      Deno.env.get('STRIPE_WEBHOOK_SECRET') as string
    );

    console.log(`Evento recebido: ${event.type}`);

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session;
      const companyId = session.client_reference_id;
      const customerId = session.customer as string;

      // Buscar detalhes da assinatura para pegar o nome do plano
      const subscription = await stripe.subscriptions.retrieve(session.subscription as string);
      const priceId = subscription.items.data[0].price.id;
      
      // Mapeamento de IDs de Preço para Nomes de Plano
      // NOTA: Você deve atualizar estes IDs com os seus IDs REAIS do Stripe
      let planName = 'Profissional'; 
      if (priceId === 'ID_DO_PRECO_ILIMITADO') planName = 'Ilimitado';

      const { error } = await supabase
        .from('companies')
        .update({
          stripe_customer_id: customerId,
          subscription_status: 'active',
          subscription_plan: planName
        })
        .eq('id', companyId);

      if (error) throw error;
      console.log(`Empresa ${companyId} atualizada com sucesso via Checkout.`);
    }

    if (event.type === 'customer.subscription.updated' || event.type === 'customer.subscription.deleted') {
      const subscription = event.data.object as Stripe.Subscription;
      const customerId = subscription.customer as string;
      const status = subscription.status === 'active' ? 'active' : 'inactive';
      
      const priceId = subscription.items.data[0].price.id;
      let planName = 'Profissional';
      if (priceId === 'ID_DO_PRECO_ILIMITADO') planName = 'Ilimitado';

      const { error } = await supabase
        .from('companies')
        .update({
          subscription_status: status,
          subscription_plan: status === 'active' ? planName : 'Gratuito'
        })
        .eq('stripe_customer_id', customerId);

      if (error) throw error;
      console.log(`Assinatura do cliente ${customerId} sincronizada.`);
    }

    return new Response(JSON.stringify({ received: true }), { status: 200 });
  } catch (err) {
    console.error(`Erro no Webhook: ${err.message}`);
    return new Response(`Erro: ${err.message}`, { status: 400 });
  }
})
