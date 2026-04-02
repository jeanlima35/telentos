-- ==============================================================================
-- SCHEMA DO SUPABASE: Banco de Talentos Pro
-- Instruções: Copie este código e cole no SQL Editor do seu projeto Supabase 
-- ==============================================================================

-- 1. EXTENSIONS
-- Habilita extensão para geração de UUIDs, caso não exista no projeto
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==============================================================================
-- 2. CRIAÇÃO DAS TABELAS
-- ==============================================================================

-- Tabela de Empresas (Multi-tenant)
CREATE TABLE public.companies (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  slug text UNIQUE NOT NULL,
  name text NOT NULL,
  phone text,
  city text NOT NULL,
  state text,
  logo text,
  active boolean DEFAULT true,
  owner_id uuid NOT NULL, -- será referenciado a seguir
  created_at timestamp with time zone DEFAULT now()
);

-- Tabela de Usuários (Estende auth.users do Supabase)
CREATE TABLE public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  name text NOT NULL,
  role text NOT NULL CHECK (role IN ('SuperAdmin', 'Proprietário', 'RH', 'Visualização')),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

-- Tabela de Vagas
CREATE TABLE public.jobs (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  requirements text,
  status text DEFAULT 'Aberta' CHECK (status IN ('Aberta', 'Fechada', 'Pausada')),
  created_at timestamp with time zone DEFAULT now()
);

-- Tabela de Candidatos (Inscrições)
CREATE TABLE public.candidates (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  job_id uuid REFERENCES public.jobs(id) ON DELETE SET NULL, -- Vínculo opcional à vaga específica
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  role text NOT NULL, -- Cargo desejado
  experience text,
  message text,
  status text DEFAULT 'Aguardando' CHECK (status IN ('Aguardando', 'Em análise', 'Entrevista', 'Contratado', 'Efetivo', 'Encerrado')),
  resume_file text, -- Caminho do arquivo PDF no storage
  created_at timestamp with time zone DEFAULT now()
);

-- Tabela de Anotações do RH sobre os Candidatos
CREATE TABLE public.candidate_notes (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  candidate_id uuid NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.users(id) DEFAULT auth.uid(),
  author_name text NOT NULL,
  text text NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);


-- ==============================================================================
-- 3. HABILITANDO O RLS (ROW LEVEL SECURITY)
-- Isso garante que, mesmo no F12, os dados fiquem seguros!
-- ==============================================================================
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_notes ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 4. POLÍTICAS DE SEGURANÇA RLS
-- ==============================================================================

-- --- COMPANIES (Empresas) ---
-- Qualquer um pode LER informações das empresas ATIVAS (para exibir a página pública)
CREATE POLICY "Public read active companies" 
  ON public.companies FOR SELECT 
  USING (active = true);

-- Apenas o dono ou usuários autenticados da empresa podem ATUALIZAR a empresa
CREATE POLICY "Users can update their company" 
  ON public.companies FOR UPDATE
  USING (
    id IN (SELECT company_id FROM public.users WHERE id = auth.uid()) OR owner_id = auth.uid()
  );

-- --- USERS (Usuários) ---
-- Usuários podem ler todos os perfis da mesma empresa
CREATE POLICY "Users can view profiles from same company"
  ON public.users FOR SELECT
  USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- O próprio usuário pode atualizar seu perfil
CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE
  USING (id = auth.uid());

-- Proprietários podem atualizar outros perfis da mesma empresa
CREATE POLICY "Owners can update company users"
  ON public.users FOR UPDATE
  USING (
    company_id IN (
      SELECT company_id FROM public.users 
      WHERE id = auth.uid() AND role = 'Proprietário'
    )
  );

-- Qualquer autenticado pode inserir um perfil (necessário para registro e criação de usuários)
CREATE POLICY "Authenticated can insert user profiles"
  ON public.users FOR INSERT
  WITH CHECK (true);

-- Proprietários podem deletar usuários da mesma empresa
CREATE POLICY "Owners can delete company users"
  ON public.users FOR DELETE
  USING (
    company_id IN (
      SELECT company_id FROM public.users 
      WHERE id = auth.uid() AND role = 'Proprietário'
    )
  );

-- --- JOBS (Vagas) ---
-- Qualquer pessoa pode LER as vagas das empresas que estão com status "Aberta" (para a página pública)
CREATE POLICY "Public read open jobs"
  ON public.jobs FOR SELECT
  USING (status = 'Aberta');

-- Usuários autenticados podem ver TODAS as vagas (fechadas/abertas) da sua própria empresa
CREATE POLICY "Users can view all jobs from their company"
  ON public.jobs FOR SELECT
  USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Apenas Proprietários e RH da empresa podem INSERIR, ATUALIZAR e DELETAR vagas
CREATE POLICY "Owners and HR can manage company jobs"
  ON public.jobs FOR ALL
  USING (
    company_id IN (
      SELECT company_id FROM public.users 
      WHERE id = auth.uid() AND role IN ('Proprietário', 'RH')
    )
  );

-- --- CANDIDATES (Candidatos) ---
-- Visitantes anônimos (ou autenticados) podem INSERIR seu currículo em qualquer empresa do portal
CREATE POLICY "Public can insert candidates" 
  ON public.candidates FOR INSERT 
  WITH CHECK (true);

-- Usuários da empresa (autenticados) podem VER, ATUALIZAR e DELETAR candidatos apenas da sua empresa
CREATE POLICY "Company users can read candidates"
  ON public.candidates FOR SELECT
  USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Company owners and HR can update candidates"
  ON public.candidates FOR UPDATE
  USING (
    company_id IN (
      SELECT company_id FROM public.users 
      WHERE id = auth.uid() AND role IN ('Proprietário', 'RH')
    )
  );

CREATE POLICY "Company owners and HR can delete candidates"
  ON public.candidates FOR DELETE
  USING (
    company_id IN (
      SELECT company_id FROM public.users 
      WHERE id = auth.uid() AND role IN ('Proprietário', 'RH')
    )
  );

-- --- CANDIDATE_NOTES (Anotações) ---
-- Apenas usuários da empresa podem LER anotações 
CREATE POLICY "Company users can read notes"
  ON public.candidate_notes FOR SELECT
  USING (
    candidate_id IN (
      SELECT id FROM public.candidates 
      WHERE company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid())
    )
  );

-- Apenas Proprietários e RH podem criar ou deletar notas
CREATE POLICY "HR and Owners can insert notes"
  ON public.candidate_notes FOR INSERT
  WITH CHECK (
    candidate_id IN (
      SELECT id FROM public.candidates 
      WHERE company_id IN (
        SELECT company_id FROM public.users 
        WHERE id = auth.uid() AND role IN ('Proprietário', 'RH')
      )
    )
  );

CREATE POLICY "Users can update and delete their own notes"
  ON public.candidate_notes FOR ALL
  USING (author_id = auth.uid());


-- ==============================================================================
-- 5. BUCKET DE STORAGE PARA ARQUIVOS (PDF)
-- ==============================================================================
-- Cria um bucket (pasta) no Supabase Storage chamado 'resumes' para guardar currículos
INSERT INTO storage.buckets (id, name, public) 
VALUES ('resumes', 'resumes', false)
ON CONFLICT (id) DO NOTHING;

-- Políticas de acesso aos arquivos PDF:
-- Qualquer um pode enviar PDF na hora de se inscrever.
CREATE POLICY "Public can upload resume" 
  ON storage.objects FOR INSERT 
  WITH CHECK (bucket_id = 'resumes');

-- Apenas os recrutadores (usuários logados) podem LER os PDFs.
-- Aqui usamos a verificação básica (usuário logado no painel).
CREATE POLICY "Authenticated users can view resumes"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'resumes' AND auth.role() = 'authenticated');
