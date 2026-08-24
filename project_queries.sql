-- Aggregating stats for all our measures across all counties
DROP VIEW everything_view;
CREATE OR REPLACE VIEW everything_view AS
  WITH retailers_count AS(
    SELECT 
      COUNT(r.*) AS n_retailers,
      r.state,
      r.county,
      r.year,
      r.acs_period_id
    FROM retailers r
    GROUP BY r.state, r.county, r.year, r.acs_period_id
  ),
  retailers_agg AS (
    SELECT 
      AVG(rc.n_retailers) AS avg_n_retailers,
      rc.state,
      rc.county,
      a.acs_period
    FROM retailers_count rc
    JOIN acs_periods a
      ON rc.acs_period_id = a.acs_period_id
    GROUP BY rc.state, rc.county, a.acs_period
  ),
  snaps_use AS(
  SELECT 
    AVG(s.tot_population) AS avg_pop,
    AVG(s.tot_population * s.participation) AS avg_poor_pop,
    ROUND(AVG(s.participation)::numeric, 2) AS avg_participation,
    a.acs_period,
    s.state,
    s.county
  FROM snaps s
  JOIN acs_periods a
    ON s.acs_period_id = a.acs_period_id
  GROUP BY s.state, s.county, a.acs_period
  )
  SELECT 
    ROUND(ra.avg_n_retailers::numeric, 2) AS avg_retailers,
    ROUND((ra.avg_n_retailers / su.avg_pop * 1000)::numeric,2) AS retailers_per_1000,
    m.net_mig_est::integer AS net_mig_est,
    ROUND(((((su.avg_pop + m.net_mig_est) - su.avg_pop) / su.avg_pop)::numeric * 100)::numeric, 2) AS pop_perc_change,
    ROUND(AVG(su.avg_pop)::numeric, 0) AS avg_pop,
    su.avg_participation AS avg_participation,
    ROUND((su.avg_participation * su.avg_pop)::numeric, 0) AS avg_on_snap,
    ra.acs_period AS acs_period,
    ra.state AS state,
    ra.county AS county,
    CASE 
      WHEN ROUND(AVG(su.avg_pop)::numeric, 2) <= 50000 THEN 'Rural'
      ELSE 'Urban'
    END AS pop_category
  FROM retailers_agg ra
  JOIN migrations m
    ON ra.acs_period = m.acs_period 
    AND ra.state = m.state_abb
    AND ra.county = UPPER(m.county)
  JOIN snaps_use su 
    ON ra.acs_period = su.acs_period 
    AND ra.state = su.state
    AND ra.county = UPPER(su.county)
  WHERE avg_participation > 0
  GROUP BY ra.state, ra.county, ra.acs_period, m.net_mig_est, ra.avg_n_retailers, su.avg_pop, su.avg_participation
  ORDER BY m.net_mig_est ASC, ra.avg_n_retailers ASC;

SELECT * FROM everything_view;

-- pulling correlations using absolute numbers
SELECT 
  corr(avg_retailers, (avg_pop * avg_participation)) AS retailers_pov,
  corr(avg_retailers, net_mig_est) AS retailers_mig,
  corr(net_mig_est, (avg_pop * avg_participation)) AS mig_pov
FROM everything_view;

-- looking at urban vs rural stats for all states (across all acs periods)
DROP VIEW v_state_agg;
CREATE OR REPLACE VIEW v_state_agg AS
  SELECT 
    state,
    pop_category,
    round(avg(retailers_per_1000)::numeric, 2) AS avg_retailers_per_1000,
    round(avg(pop_perc_change)::numeric, 2) AS avg_pop_perc_change,
    round(avg(avg_pop)::numeric, 2) AS avg_pop,
    round(avg(avg_participation)::numeric, 2) AS avg_participation,
    round(avg(avg_on_snap)::numeric, 2) AS avg_on_snap
  FROM everything_view
  GROUP BY state, pop_category
  ORDER BY state ASC;

SELECT * FROM v_state_agg;

-- finding correlations between all of the variables
SELECT corr(pop_perc_change, avg_participation) AS mig_part,
    corr(pop_perc_change, retailers_per_1000) AS mig_ret
FROM everything_view;


-- Sorting by counties with the highest need for SNAP retailers–poverty level and also 
-- sorting by the counties with the lowest availability of SNAP retailers.
CREATE OR REPLACE VIEW snap_v_pov AS
  WITH retailers_per_year AS(
    SELECT 
      COUNT(*) AS n_retailers,
      state,
      UPPER(county) AS county
    FROM retailers
    GROUP BY year, state, county
  )
  SELECT 
    ROUND(AVG(s.participation)::numeric, 2) AS avg_poor,
    ROUND(AVG(r.n_retailers)::numeric, 2) AS avg_retailers,
    ROUND((AVG(r.n_retailers)::numeric / AVG(s.tot_population)::numeric) * 1000, 2) AS retailers_per_1000,
    ROUND(AVG(s.tot_population)::numeric, 0) AS avg_pop,
    s.county,
    s.state,
    CASE
      WHEN AVG(s.tot_population) > 50000 THEN 'Urban'
      ELSE 'Rural'
    END AS pop_category
  FROM snaps s
  JOIN retailers_per_year r
    ON s.state = r.state AND s.county = UPPER(r.county)
  WHERE s.participation > 0
  GROUP BY s.state, s.county
  ORDER BY avg_poor DESC, retailers_per_1000 ASC;



-- finding number of most impoverished counties that are rural
WITH pov_ranked AS(
  SELECT 
    state,
    county,
    AVG(participation) AS avg_participation,
    rank() OVER(ORDER BY AVG(participation) DESC) AS county_pov_rank,
    CASE
      WHEN AVG(tot_population) > 50000 THEN 'Urban'
      ELSE 'Rural'
    END AS pop_category
  FROM snaps
  GROUP BY state, county
)
SELECT pop_category,
  COUNT(pop_category)
FROM pov_ranked
WHERE avg_participation >= 0.25
GROUP BY pop_category;

