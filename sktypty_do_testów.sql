select * from manufacturers m, 
select * from models m2;
select * from analyzers a;
select * from statuses s; 
select * from analyzer_locations al; 
select * from locations l;
select * from laboratories lb;
select * from fees f;
select * from test_counts t;
select * from models m;

"""Przed wykonaniem testów należy uzupełnić BD danymi testowymi. 
Wszystkie testy na danych testowych załadowanych przeze mnie przeszły pozytywnie."""

--usuń analizator z laboratorium 1 i przenieś do laboratorium 2

-- 1. usuń analizator z laboratorium
update analyzer_locations set end_date='now' where analyzer_location_id=1;

-- 2. przenieś analizator do laboratorium 2
insert into analyzer_locations 
(analyzer_id, location_id,laboratory_id, analyzer_name, marcel_symbol, start_date) 
values (3,1,3,'Analizator lab 2','TGBB21','now');

-- pokaż historę lokalizacji analizatora
select l.symbol ||' - '|| l.name as laboratorium, 
	al.marcel_symbol ||' - '||al.analyzer_name as analizator, 
	a.serial_number as "nr seryjny", 
	al.start_date as "początek pracy", 
	al.end_date as "koniec pracy"
from analyzer_locations al
	left join analyzers a on a.analyzer_id=al.analyzer_id
	left join laboratories l on l.laboratory_id=al.laboratory_id
where a.serial_number = '10504';


--pokaż analizatory w laboratorium 1
select l.symbol ||' - '|| l.name as laboratorium, 
	al.marcel_symbol ||' - '||al.analyzer_name as analizator, 
	a.serial_number as "nr seryjny", 
	al.start_date as "początek pracy", 
	al.end_date as "koniec pracy", 
	s.name as status
from analyzer_locations al
	left join laboratories l on l.laboratory_id=al.laboratory_id
	left join analyzers a on a.analyzer_id =al.analyzer_id
	left join statuses s on a.status_id =s.status_id
where l.symbol='LAB1' and al.end_date is null

--pokaż wszystkie analizatory danego dostawcy
select a.serial_number, a.name, m2.name, m.name from analyzers a 
left join models m2 on m2.model_id =a.model_id 
left join manufacturers m on m.manufacturer_id =m2.model_id
where m.name='Abbott'

--dodanie nowego analizatora
insert into analyzers 
(serial_number, name, model_id, production_year, ownership_type, purchase_date, status_id) 
values ('ABC-12-1-444','Zybio U1600',7,'2024','lease','now', 1);

--przypisz analizator do lokalizacji 
insert into analyzer_locations 
(analyzer_id, location_id,laboratory_id, analyzer_name, marcel_symbol, start_date ) 
values (11,1,3,'Zybio U1600 Lab2','L2ZYBI','now');

--sprawdz nieuzywane analizatory
select 
	m."name" as "producent",
	m2.name as "model",
	a.name as "nazwa analizatora", 
	a.serial_number as "nr seryjny", 
	a.ownership_type as "typ własnosci",
	al.laboratory_id
from analyzers a 
	left join analyzer_locations al on a.analyzer_id =al.analyzer_id
	left join models m2 on m2.model_id =a.model_id 	
	left join manufacturers m on m.manufacturer_id =m2.manufacturer_id
where al.laboratory_id is null;

-- sprawdź ilość badań wykonanych przez analizator
select 
	al.marcel_symbol as "symbol analizatora",  
	DATE_PART('year',t.date)||'-'||DATE_PART('month', t.date)  as "rok i miesiąc",
	t.count as "suma badań"
from test_counts t
left join analyzer_locations al on al.analyzer_location_id=t.analyzer_location_id
left join laboratories l on l.laboratory_id=al.laboratory_id
where l.symbol = 'LAB1';


-- zakończ pracę analizatora w organizacji
update analyzers  
set status_id=3, retirement_date='now' 
where analyzer_id=12;

-- sprawdź koszt analizatorów w lokalizacji 
select al.marcel_symbol as "symbol analizatora",  
	f.monthly_lease_fee ||' zł' as "miesięczny koszt"
from fees f
	left join analyzers a on a.analyzer_id =f.analyzer_id
	left join analyzer_locations al on a.analyzer_id =al.analyzer_id
	left join laboratories l on l.laboratory_id=al.laboratory_id
where l.symbol = 'LAB1'; 


--test roli "rapo_role"


--odczyt informacji
select * from statuses;

--dodawanie informacji
insert into statuses (name) values ('raportowy');



--edytowanie danych
update analyzers  
set status_id=3, retirement_date='now' 
where analyzer_id=11;