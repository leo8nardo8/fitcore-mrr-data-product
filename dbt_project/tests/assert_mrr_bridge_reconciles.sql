/*
  REGRA CONTÁBIL: a ponte de MRR precisa fechar.

    abertura + novo + reativação + expansão - contração - churn = fechamento

  e a abertura de um mês precisa ser igual ao fechamento do mês anterior.

  Os dois lados vêm de cálculos independentes (movimentos cliente a cliente
  vs. foto das assinaturas ativas), então qualquer divergência indica erro
  de lógica ou de dados. Retorna as linhas que violam a regra (0 linhas =
  aprovado). Tolerância de R$ 0,01 para arredondamento.

  O teste roda sobre a int_mrr_bridge_monthly, e não sobre o mart: no
  `dbt build`, testes de um modelo rodam antes dos seus filhos, então uma
  ponte que não fecha impede a publicação do fct_mrr_monthly.
*/
with bridge as (
    select
        month_start,
        opening_mrr,
        closing_mrr,
        opening_mrr + new_mrr + reactivation_mrr + expansion_mrr
            - contraction_mrr - churned_mrr             as computed_closing,
        lag(closing_mrr) over (order by month_start)    as previous_closing
    from {{ ref('int_mrr_bridge_monthly') }}
)

select
    month_start,
    opening_mrr,
    previous_closing,
    closing_mrr,
    computed_closing,
    closing_mrr - computed_closing as bridge_gap
from bridge
where abs(closing_mrr - computed_closing) > 0.01
   or (previous_closing is not null and abs(opening_mrr - previous_closing) > 0.01)
