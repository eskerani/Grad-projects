SELECT 
  COUNT(r.store_name) AS n_retailers, 
  m.net_mig_est,
  r.county,
  r.state
FROM retailers r
JOIN migrations m 
  ON m.county = r.county AND m.state = r.state
--WHERE r.year < 2021 AND r.year > 2015
GROUP BY r.county, r.state, m.net_mig_est
ORDER BY net_mig_est ASC;



-- NUMBER OF RETAILERS VS NET MIGRATION
DROP VIEW retailers_migration;
CREATE OR REPLACE VIEW retailers_migration AS
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
    m.net_mig_est AS net_mig_est,
    ROUND(((((su.avg_pop + m.net_mig_est) - su.avg_pop) / su.avg_pop)::numeric * 100)::numeric, 2) AS pop_perc_change,
    su.avg_participation AS avg_participation,
    ra.acs_period AS acs_period,
    ra.state AS state,
    ra.county AS county
  FROM retailers_agg ra
  JOIN migrations m
    ON ra.acs_period = m.acs_period 
    AND ra.state = m.state_abb
    AND ra.county = UPPER(m.county)
  JOIN snaps_use su 
    ON ra.acs_period = su.acs_period 
    AND ra.state = su.state
    AND ra.county = UPPER(su.county)
  GROUP BY ra.state, ra.county, ra.acs_period, m.net_mig_est, ra.avg_n_retailers, su.avg_pop, su.avg_participation
  ORDER BY m.net_mig_est ASC, ra.avg_n_retailers ASC;

SELECT * FROM retailers_migration;

SELECT corr(pop_perc_change, avg_participation) AS mig_part,
    corr(pop_perc_change, retailers_per_1000) AS mig_ret
FROM retailers_migration;

-- might need to join this to snaps after all to make it make sense
SELECT 
  corr(avg_retailers, net_mig_est) AS ret_mig_corr
FROM retailers_migration;

-- Sorting by counties with the highest need for SNAP retailers–poverty level–and also 
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
      WHEN AVG(s.tot_population) > 200000 THEN 'Urban'
      ELSE 'Rural'
    END AS pop_category
  FROM snaps s
  JOIN retailers_per_year r
    ON s.state = r.state AND s.county = UPPER(r.county)
  WHERE s.participation > 0
  GROUP BY s.state, s.county
  ORDER BY avg_poor DESC, retailers_per_1000 ASC;


select * from snap_v_pov;

select
  corr(avg_poor, avg_retailers) AS poor_retailers
FROM snap_v_pov;



-- finding number of most impoverished counties that are rural
WITH pov_ranked AS(
  SELECT 
    state,
    county,
    AVG(participation) AS avg_participation,
    rank() OVER(ORDER BY AVG(participation) DESC) AS county_pov_rank,
    CASE
      WHEN AVG(tot_population) > 200000 THEN 'Urban'
      ELSE 'Rural'
    END AS pop_category
  FROM snaps
  GROUP BY state, county
)
SELECT pop_category,
  COUNT(pop_category)
FROM pov_ranked
WHERE county_pov_rank <= 100
GROUP BY pop_category;


rank() OVER(ORDER BY COUNT(y.trip_id) DESC) AS trip_rank
