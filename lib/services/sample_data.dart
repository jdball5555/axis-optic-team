// TEMPORARY sample data for testing the schedule with a realistic store.
//
// The team and the week in [_sampleWeek] are made up, shaped like a typical
// quick-service store (titles, areas, tags, who works when, Front of house and
// Kitchen). Names, availability, time off, pay and login emails are all fake.
//
// Seeding a store:
//  * replaces its team (stores/{id}/users) with these people, each with a
//    fake login (/users/seed_login_*, role team_member, linked by email and
//    userId like a real account; nobody can actually sign in with them)
//  * writes their availability (on the member and in active_availability),
//    some time off requests (approved, pending and denied) and a training
//    review (3 new hires + 2 part way through are in training)
//  * sets up titles, tags, the In Training checklist, positions, and two
//    schedules: Front of House (main) and Kitchen
//  * builds a template per weekday and schedule from the sample week, puts
//    the sample week on THIS week's schedule (posted), and applies the
//    templates to NEXT week with nobody on them, ready to build.

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/schedule_models.dart';
import '../models/store_settings_model.dart';
import '../models/title_journey.dart';
import '../models/user_model.dart';
import '../ui/views/schedule/position_ops.dart';
import 'schedule_repository.dart';

// =============================================================================
// Names: everyone gets a new, random name each time the sample data is added
// (the rest of each person stays the same), so seeding again, or seeding
// another store, looks like a new team.
// =============================================================================

/// First names, with a short name some of them go by.
const _firstNames = <(String, String?)>[
  ('Aaliyah', null),
  ('Abigail', null),
  ('Adrian', null),
  ('Aiden', null),
  ('Alejandro', null),
  ('Alexander', 'Alex'),
  ('Alyssa', null),
  ('Amara', null),
  ('Andre', null),
  ('Angela', null),
  ('Anthony', 'Tony'),
  ('Ariana', null),
  ('Austin', null),
  ('Avery', null),
  ('Bailey', null),
  ('Benjamin', 'Ben'),
  ('Brandon', null),
  ('Brianna', null),
  ('Caleb', null),
  ('Camila', null),
  ('Carmen', null),
  ('Carter', null),
  ('Cecilia', null),
  ('Chloe', null),
  ('Christopher', 'Chris'),
  ('Claire', null),
  ('Cole', null),
  ('Connor', null),
  ('Daniela', 'Dani'),
  ('Darius', null),
  ('Delilah', null),
  ('Destiny', null),
  ('Diego', null),
  ('Dominic', null),
  ('Eduardo', null),
  ('Elena', null),
  ('Elijah', null),
  ('Elizabeth', 'Liz'),
  ('Emilia', null),
  ('Emmanuel', null),
  ('Erica', null),
  ('Esperanza', null),
  ('Ethan', null),
  ('Evelyn', null),
  ('Fatima', null),
  ('Felix', null),
  ('Gabriel', 'Gabe'),
  ('Gabriela', null),
  ('Gianna', null),
  ('Grace', null),
  ('Hannah', null),
  ('Harper', null),
  ('Hector', null),
  ('Isabella', 'Bella'),
  ('Isaiah', null),
  ('Ivan', null),
  ('Jacob', null),
  ('Jada', null),
  ('Jasmine', null),
  ('Javier', null),
  ('Jayden', null),
  ('Jordan', null),
  ('Josephine', 'Josie'),
  ('Joshua', 'Josh'),
  ('Julian', null),
  ('Kaitlyn', null),
  ('Kayla', null),
  ('Keanu', null),
  ('Kendall', null),
  ('Khalil', null),
  ('Kiara', null),
  ('Landon', null),
  ('Layla', null),
  ('Leah', null),
  ('Leonardo', 'Leo'),
  ('Liam', null),
  ('Lucas', null),
  ('Luciana', null),
  ('Mackenzie', null),
  ('Madeline', 'Maddie'),
  ('Malik', null),
  ('Marco', null),
  ('Mariana', null),
  ('Marisol', null),
  ('Mason', null),
  ('Mateo', null),
  ('Maya', null),
  ('Micah', null),
  ('Miguel', null),
  ('Mila', null),
  ('Naomi', null),
  ('Natalia', null),
  ('Nathaniel', 'Nate'),
  ('Nicholas', 'Nick'),
  ('Nina', null),
  ('Noah', null),
  ('Nora', null),
  ('Olivia', null),
  ('Omar', null),
  ('Oscar', null),
  ('Paige', null),
  ('Parker', null),
  ('Priya', null),
  ('Quinn', null),
  ('Rafael', null),
  ('Reese', null),
  ('Ricardo', null),
  ('Riley', null),
  ('Rosa', null),
  ('Ruby', null),
  ('Ryan', null),
  ('Samantha', 'Sam'),
  ('Santiago', null),
  ('Savannah', null),
  ('Sebastian', null),
  ('Serena', null),
  ('Sienna', null),
  ('Sofia', null),
  ('Stella', null),
  ('Taylor', null),
  ('Terrell', null),
  ('Trinity', null),
  ('Tyler', null),
  ('Valentina', null),
  ('Valeria', null),
  ('Victoria', 'Tori'),
  ('Vivian', null),
  ('Wesley', null),
  ('Xavier', null),
  ('Yasmin', null),
  ('Zachary', 'Zach'),
  ('Zoe', null),
];

const _lastNames = <String>[
  'Acosta',
  'Adams',
  'Aguilar',
  'Alvarez',
  'Anderson',
  'Bailey',
  'Baker',
  'Banks',
  'Barnes',
  'Bell',
  'Bennett',
  'Brooks',
  'Bryant',
  'Butler',
  'Campbell',
  'Carter',
  'Castillo',
  'Chavez',
  'Coleman',
  'Collins',
  'Cooper',
  'Cruz',
  'Delgado',
  'Diaz',
  'Edwards',
  'Ellis',
  'Espinoza',
  'Evans',
  'Fisher',
  'Flores',
  'Foster',
  'Garza',
  'Gibson',
  'Gomez',
  'Graham',
  'Griffin',
  'Guerrero',
  'Hamilton',
  'Harper',
  'Hayes',
  'Henderson',
  'Hernandez',
  'Holmes',
  'Howard',
  'Hughes',
  'Jenkins',
  'Jimenez',
  'Jordan',
  'Kelly',
  'Kennedy',
  'Kim',
  'Le',
  'Long',
  'Mendez',
  'Meyer',
  'Miller',
  'Mitchell',
  'Moreno',
  'Morgan',
  'Murphy',
  'Myers',
  'Nguyen',
  'Ortiz',
  'Owens',
  'Palmer',
  'Patel',
  'Perez',
  'Perry',
  'Peterson',
  'Powell',
  'Price',
  'Ramirez',
  'Ramos',
  'Reed',
  'Reyes',
  'Reynolds',
  'Rivera',
  'Roberts',
  'Robinson',
  'Rojas',
  'Russell',
  'Salazar',
  'Sanders',
  'Santos',
  'Shaw',
  'Simmons',
  'Soto',
  'Spencer',
  'Stewart',
  'Sullivan',
  'Torres',
  'Tran',
  'Tucker',
  'Turner',
  'Vargas',
  'Vasquez',
  'Wagner',
  'Walker',
  'Wallace',
  'Ward',
  'Warren',
  'Washington',
  'Watson',
  'Wells',
  'West',
  'Wheeler',
  'Williams',
  'Wood',
  'Wright',
  'Young',
];

// =============================================================================
// The team
// =============================================================================

class _Person {
  final String id; // short key used in the sample week (names are random)
  final String title;
  final String designation;
  final List<String> tags;
  final String area; // roster position: SVC, DT, KT, DIR
  final String time; // Daytime / Night
  final String? permit; // food handler expiration (yyyy-MM-dd)
  final String? mgrPermit;
  final String start; // yyyy-MM-dd
  final int? checklistDone; // In Training checklist items done
  final bool checklistComplete;
  final bool leaving;

  /// New hire: started a few days before the seed date.
  final int? startedDaysAgo;

  const _Person(
    this.id, {
    required this.title,
    required this.designation,
    this.tags = const [],
    required this.area,
    required this.time,
    this.permit,
    this.mgrPermit,
    this.start = '',
    this.checklistDone,
    this.checklistComplete = false,
    this.leaving = false,
    this.startedDaysAgo,
  });
}

const _tm = 'Team Member';
const _it = 'In Training';

const _people = <_Person>[
  // --- In training ---------------------------------------------------------
  _Person(
    'p01',
    title: _it,
    designation: 'Adult',
    area: 'DT',
    time: 'Daytime',
    start: '2026-09-20',
    checklistDone: 4,
  ),
  _Person(
    'p02',
    title: _it,
    designation: 'Adult',
    area: 'SVC',
    time: 'Daytime',
    start: '2026-09-06',
    checklistDone: 3,
  ),
  _Person(
    'p03',
    title: _it,
    designation: 'High School',
    area: 'DT',
    time: 'Night',
    permit: '2027-10-24',
    start: '2026-10-07',
    checklistDone: 6,
  ),
  _Person(
    'p04',
    title: _it,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    permit: '2028-10-08',
    start: '2026-09-15',
    checklistDone: 8,
  ),
  _Person(
    'p05',
    title: _it,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    start: '2026-09-03',
    checklistComplete: true,
  ),
  _Person(
    'p06',
    title: _it,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    start: '2026-08-30',
    checklistComplete: true,
  ),
  _Person(
    'p07',
    title: _it,
    designation: 'College',
    area: 'SVC',
    time: 'Daytime',
    permit: '2028-06-12',
    start: '2026-08-22',
    checklistComplete: true,
  ),
  _Person(
    'p08',
    title: _it,
    designation: 'College',
    area: 'DT',
    time: 'Night',
    permit: '2028-08-05',
    start: '2026-07-31',
    checklistDone: 6,
  ),
  _Person(
    'p09',
    title: _it,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    start: '2026-07-14',
    checklistDone: 8,
  ),
  _Person(
    'p10',
    title: _it,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    permit: '2028-09-02',
    start: '2026-06-02',
    checklistDone: 7,
  ),
  // New hires with no shifts yet: the training flow picks them up.
  _Person(
    'p11',
    title: _it,
    designation: 'High School',
    area: 'DT',
    time: 'Night',
    startedDaysAgo: 4,
    checklistDone: 1,
  ),
  _Person(
    'p12',
    title: _it,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    startedDaysAgo: 2,
    checklistDone: 0,
  ),
  _Person(
    'p13',
    title: _it,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    startedDaysAgo: 3,
    checklistDone: 0,
  ),

  // --- Team members -----------------------------------------------------------
  _Person(
    'p14',
    title: _tm,
    designation: 'Adult',
    area: 'DT',
    time: 'Daytime',
    permit: '2028-07-29',
    start: '2026-08-10',
  ),
  _Person(
    'p15',
    title: _tm,
    designation: 'Adult',
    area: 'SVC',
    time: 'Daytime',
    permit: '2028-06-10',
    start: '2026-08-05',
  ),
  _Person(
    'p16',
    title: _tm,
    designation: 'High School',
    area: 'KT',
    time: 'Night',
    start: '2026-07-30',
  ),
  _Person(
    'p17',
    title: _tm,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    start: '2026-07-01',
  ),
  _Person(
    'p18',
    title: _tm,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    permit: '2028-11-02',
    start: '2026-06-19',
  ),
  _Person(
    'p19',
    title: _tm,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    permit: '2028-08-21',
    start: '2026-03-29',
  ),
  _Person(
    'p20',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    permit: '2027-07-27',
    start: '2026-04-20',
  ),
  _Person(
    'p21',
    title: _tm,
    designation: 'College',
    area: 'DT',
    time: 'Night',
    permit: '2028-09-03',
    start: '2026-03-23',
    leaving: true,
  ),
  _Person(
    'p22',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    permit: '2028-07-19',
    start: '2026-03-14',
  ),
  _Person(
    'p23',
    title: _tm,
    designation: 'Adult',
    area: 'DT',
    time: 'Daytime',
    start: '2026-03-13',
  ),
  _Person(
    'p24',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    permit: '2028-02-19',
    start: '2026-01-31',
  ),
  _Person(
    'p25',
    title: _tm,
    designation: 'High School',
    area: 'DT',
    time: 'Night',
    permit: '2026-11-01',
    start: '2026-01-18',
  ),
  _Person(
    'p26',
    title: _tm,
    designation: 'High School',
    area: 'DT',
    time: 'Night',
    permit: '2028-02-01',
    start: '2026-01-23',
  ),
  _Person(
    'p27',
    title: _tm,
    designation: 'High School',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Night',
    permit: '2028-01-11',
    start: '2026-01-01',
  ),
  _Person(
    'p28',
    title: _tm,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    permit: '2027-08-03',
    start: '2025-07-12',
  ),
  _Person(
    'p29',
    title: _tm,
    designation: 'Adult',
    tags: ['Truck'],
    area: 'DT',
    time: 'Daytime',
    permit: '2027-07-04',
    start: '2025-07-03',
  ),
  _Person(
    'p30',
    title: _tm,
    designation: 'High School',
    area: 'SVC',
    time: 'Night',
    permit: '2027-06-01',
    start: '2025-05-24',
  ),
  _Person(
    'p31',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    permit: '2027-08-07',
    start: '2025-06-04',
  ),
  _Person(
    'p32',
    title: _tm,
    designation: 'College',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Daytime',
    permit: '2025-09-16',
    start: '2025-04-29',
  ),
  _Person(
    'p33',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    permit: '2027-10-10',
    start: '2025-04-22',
  ),
  _Person(
    'p34',
    title: _tm,
    designation: 'High School',
    area: 'DT',
    time: 'Night',
    permit: '2027-03-22',
    start: '2025-03-15',
  ),
  _Person(
    'p35',
    title: _tm,
    designation: 'High School',
    area: 'DT',
    time: 'Night',
    permit: '2027-11-15',
    start: '2025-01-16',
  ),
  _Person(
    'p36',
    title: _tm,
    designation: 'College',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Night',
    permit: '2027-01-06',
    start: '2024-11-29',
  ),
  _Person(
    'p37',
    title: _tm,
    designation: 'College',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Night',
    permit: '2027-08-30',
    start: '2024-08-23',
  ),
  _Person(
    'p38',
    title: _tm,
    designation: 'College',
    area: 'DT',
    time: 'Night',
    permit: '2026-10-31',
    start: '2024-10-31',
  ),
  _Person(
    'p39',
    title: _tm,
    designation: 'High School',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Night',
    permit: '2026-10-05',
    start: '2024-10-05',
  ),
  _Person(
    'p40',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    start: '2024-10-05',
  ),
  _Person(
    'p41',
    title: _tm,
    designation: 'College',
    area: 'DT',
    time: 'Night',
    permit: '2028-08-06',
    start: '2024-08-06',
  ),
  _Person(
    'p42',
    title: _tm,
    designation: 'College',
    area: 'SVC',
    time: 'Daytime',
    permit: '2026-03-22',
    start: '2024-03-20',
  ),
  _Person(
    'p43',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    start: '2023-09-26',
  ),
  _Person(
    'p44',
    title: _tm,
    designation: 'College',
    tags: ['Trainer', 'Truck'],
    area: 'SVC',
    time: 'Daytime',
    permit: '2027-07-13',
    start: '2023-08-11',
  ),
  _Person(
    'p45',
    title: _tm,
    designation: 'Adult',
    area: 'DT',
    time: 'Daytime',
    start: '2022-08-03',
  ),
  _Person(
    'p46',
    title: _tm,
    designation: 'Adult',
    area: 'SVC',
    time: 'Daytime',
    permit: '2027-07-30',
    start: '2022-05-08',
  ),
  _Person(
    'p47',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    permit: '2030-03-13',
    start: '2022-01-16',
  ),
  _Person(
    'p48',
    title: _tm,
    designation: 'Adult',
    area: 'SVC',
    time: 'Night',
    permit: '2026-08-24',
    start: '2021-09-17',
  ),
  _Person(
    'p49',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    permit: '2027-10-13',
    start: '2021-09-14',
  ),
  _Person(
    'p50',
    title: _tm,
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    permit: '2027-08-14',
    start: '2017-10-31',
  ),

  // --- Champions ----------------------------------------------------------------
  _Person(
    'p51',
    title: 'Champion',
    designation: 'High School',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Night',
    permit: '2028-08-15',
    start: '2024-10-22',
  ),
  _Person(
    'p52',
    title: 'Champion',
    designation: 'Adult',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Daytime',
    permit: '2027-01-04',
    start: '2021-09-07',
  ),

  // --- Seasonal (away at school: no availability) ----------------------------------
  _Person(
    'p53',
    title: 'Seasonal',
    designation: 'College',
    area: 'SVC',
    time: 'Daytime',
    permit: '2026-11-09',
    start: '2024-10-31',
  ),
  _Person(
    'p54',
    title: 'Seasonal',
    designation: 'College',
    tags: ['Trainer'],
    area: 'DT',
    time: 'Daytime',
    permit: '2026-03-25',
    start: '2024-03-21',
  ),
  _Person(
    'p55',
    title: 'Seasonal',
    designation: 'College',
    area: 'DT',
    time: 'Daytime',
    start: '2024-02-12',
  ),
  _Person(
    'p56',
    title: 'Seasonal',
    designation: 'College',
    tags: ['Trainer'],
    area: 'SVC',
    time: 'Daytime',
    start: '2021-06-06',
  ),

  // --- Leaders --------------------------------------------------------------------
  _Person(
    'p57',
    title: 'Leader',
    designation: 'Adult',
    tags: ['Driver'],
    area: 'SVC',
    time: 'Daytime',
    start: '2026-02-25',
  ),
  _Person(
    'p58',
    title: 'Leader',
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    permit: '2030-02-12',
    mgrPermit: '2030-02-23',
    start: '2023-06-16',
  ),
  _Person(
    'p59',
    title: 'Leader',
    designation: 'Adult',
    tags: ['Driver'],
    area: 'SVC',
    time: 'Night',
    start: '2023-04-08',
  ),
  _Person(
    'p60',
    title: 'Leader',
    designation: 'College',
    tags: ['Driver'],
    area: 'DT',
    time: 'Night',
    permit: '2027-04-26',
    mgrPermit: '2028-01-30',
    start: '2022-04-29',
  ),
  _Person(
    'p61',
    title: 'Leader',
    designation: 'Adult',
    area: 'KT',
    time: 'Daytime',
    permit: '2030-03-09',
    mgrPermit: '2030-03-13',
    start: '2021-08-27',
  ),
  _Person(
    'p62',
    title: 'Leader',
    designation: 'Adult',
    area: 'KT',
    time: 'Night',
    permit: '2030-02-22',
    mgrPermit: '2030-03-10',
    start: '2013-08-17',
  ),
  _Person(
    'p63',
    title: 'Leader',
    designation: 'Adult',
    area: 'DT',
    time: 'Daytime',
    permit: '2026-11-25',
    mgrPermit: '2026-12-10',
    start: '2013-01-21',
  ),

  // --- Directors ------------------------------------------------------------------
  _Person(
    'p64',
    title: 'Director',
    designation: 'Adult',
    tags: ['Driver'],
    area: 'DIR',
    time: 'Daytime',
    permit: '2028-08-10',
    mgrPermit: '2028-08-07',
    start: '2022-10-16',
  ),
  _Person(
    'p65',
    title: 'Director',
    designation: 'Adult',
    tags: ['Driver'],
    area: 'DIR',
    time: 'Daytime',
    permit: '2028-07-23',
    mgrPermit: '2028-07-17',
    start: '2016-09-21',
  ),
  _Person(
    'p66',
    title: 'Director',
    designation: 'Adult',
    tags: ['Driver'],
    area: 'DIR',
    time: 'Daytime',
    permit: '2030-03-28',
    mgrPermit: '2030-03-07',
    start: '2012-04-04',
  ),
];

// =============================================================================
// The sample week (Monday → Saturday; the store is closed Sunday)
// =============================================================================
//
// One line per block: `who start-end kind`. A person's blocks on the same
// day and schedule become one shift. Kinds:
//   BOH / PREP          kitchen
//   FOH / HOST          front of house (HOST = Dining Room Host)
//   TRAINER / TRAINEE   a training pair (same times)
//   TRUCK               the schedule of the person's area
//   ADMIN               admin time on the person's shift (off the floor,
//                       not a template bar)
// `house-k` / `house-f` = a slot nobody was on yet (kitchen / front).

const _sampleWeek = <String>[
  // Monday
  '''
p43 05:15-13:00 BOH
p05 05:15-14:30 BOH
p61 05:15-16:00 BOH
p58 05:15-15:00 BOH
p50 06:00-15:00 BOH
p06 06:00-15:00 BOH
p47 07:00-16:00 BOH
p22 09:00-19:00 BOH
p62 13:00-22:45 BOH
p43 13:00-14:00 PREP
p20 15:00-22:45 BOH
p33 15:00-22:45 BOH
p24 15:00-22:45 BOH
p31 16:00-22:45 BOH
p40 16:00-22:45 BOH
p23 05:15-14:00 FOH
p52 05:15-13:00 FOH
p57 05:45-16:00 FOH
p32 06:00-10:00 FOH
p07 06:30-14:30 FOH
p45 07:00-15:00 FOH
p02 07:00-10:30 FOH
p59 09:00-18:00 FOH
p63 10:00-10:30 FOH
p42 11:00-16:00 HOST
p14 11:00-16:00 HOST
p15 11:00-18:00 FOH
p36 12:00-20:00 FOH
p01 14:30-19:00 FOH
p60 15:00-22:45 FOH
p38 15:30-20:00 FOH
p51 16:00-22:45 FOH
p14 16:00-17:00 FOH
p26 16:00-21:00 FOH
p28 16:00-20:00 FOH
p21 16:30-21:00 FOH
p10 17:00-19:00 FOH
p48 17:00-22:00 HOST
p35 17:00-21:30 FOH
p25 18:00-22:45 FOH
p17 18:00-22:45 FOH
p19 18:00-22:45 FOH
p37 20:00-22:00 FOH
p50 05:15-06:00 TRUCK
p06 05:15-06:00 TRUCK
p60 14:00-15:00 ADMIN
p14 17:00-20:00 ADMIN
p37 17:00-20:00 ADMIN
p32 10:00-14:30 TRAINER
p01 10:00-14:30 TRAINEE
p63 10:30-15:30 TRAINER
p02 10:30-15:30 TRAINEE
''',
  // Tuesday
  '''
p43 05:15-13:00 BOH
p61 05:15-14:00 BOH
p47 06:00-16:00 BOH
p22 06:00-13:00 BOH
p05 06:00-15:00 BOH
p06 06:00-15:00 BOH
p58 07:00-16:00 BOH
p62 10:00-22:45 BOH
p16 10:00-19:00 BOH
p43 13:00-14:00 PREP
p43 14:00-14:30 BOH
p49 15:00-22:45 BOH
p33 15:00-22:45 BOH
p24 15:00-22:45 BOH
p31 16:00-22:45 BOH
p40 16:00-22:45 BOH
p23 05:15-13:30 FOH
p52 05:15-13:00 FOH
p57 05:45-16:00 FOH
p32 06:00-14:00 FOH
p29 06:00-13:30 FOH
p07 07:00-15:00 FOH
p45 07:00-15:00 FOH
p60 08:00-12:00 FOH
p21 08:00-16:00 FOH
p59 10:00-19:00 FOH
p63 10:00-22:45 FOH
p14 10:30-18:00 FOH
p36 12:00-18:00 FOH
p46 12:00-17:00 HOST
p08 13:00-18:00 FOH
p35 15:00-20:00 FOH
p28 16:00-20:00 FOH
p04 16:30-21:30 FOH
p48 17:00-22:00 HOST
p18 17:00-22:00 FOH
p17 17:00-21:00 FOH
p27 18:00-22:45 FOH
p25 18:00-22:45 FOH
p30 18:00-22:45 FOH
p44 19:15-22:45 FOH
p37 19:15-22:00 FOH
p22 05:15-06:00 TRUCK
p06 05:15-06:00 TRUCK
p29 13:30-15:00 TRUCK
p44 16:45-19:15 ADMIN
p10 17:00-19:00 ADMIN
p37 17:00-19:15 ADMIN
''',
  // Wednesday
  '''
p61 05:15-15:00 BOH
p58 05:15-15:00 BOH
p47 06:00-16:00 BOH
p50 06:00-15:00 BOH
p22 06:00-14:30 BOH
p06 06:00-11:30 BOH
p40 07:00-14:00 BOH
p62 11:00-22:45 BOH
p16 11:30-20:00 BOH
p40 14:00-15:00 PREP
p49 15:00-22:45 BOH
p20 15:00-22:45 BOH
p33 15:00-22:45 BOH
p24 15:00-22:45 BOH
p31 16:00-22:45 BOH
p23 05:15-13:30 FOH
p52 05:15-13:00 FOH
p57 05:45-16:00 FOH
p07 06:00-15:00 FOH
p29 06:00-14:00 FOH
p45 07:00-15:00 FOH
p02 07:00-14:00 FOH
p63 10:00-10:30 FOH
p59 11:00-19:00 FOH
p46 11:00-16:00 HOST
p15 11:30-18:00 FOH
p08 14:00-20:00 FOH
p14 14:00-22:45 FOH
p42 15:00-17:00 FOH
p01 15:00-18:00 FOH
p26 16:00-21:00 FOH
p42 17:00-22:00 HOST
p60 17:00-22:45 FOH
p35 17:00-22:00 FOH
p34 18:00-22:45 FOH
p38 18:00-22:00 FOH
p50 05:15-06:00 TRUCK
p06 05:15-06:00 TRUCK
p44 15:00-16:30 TRUCK
p63 10:30-15:00 TRAINER
p01 10:30-15:00 TRAINEE
p44 16:30-22:45 TRAINER
p03 16:30-22:45 TRAINEE
''',
  // Thursday
  '''
p43 05:15-15:00 BOH
p61 05:15-14:00 BOH
p50 06:00-15:00 BOH
p05 06:00-13:00 BOH
p06 06:00-13:00 BOH
p58 06:00-16:00 BOH
p22 07:00-16:00 BOH
p62 11:00-22:45 BOH
p05 13:00-14:00 PREP
p16 13:00-21:00 BOH
p05 14:00-15:00 BOH
p49 15:00-22:45 BOH
p20 15:00-22:45 BOH
p33 15:00-22:45 BOH
p31 16:00-22:45 BOH
p40 16:00-22:45 BOH
p52 05:15-13:00 FOH
p29 05:15-13:30 FOH
p57 05:45-16:00 FOH
p07 06:00-14:00 FOH
p45 06:00-14:00 FOH
p36 07:00-16:00 FOH
p02 07:00-10:00 FOH
p21 10:00-16:00 FOH
p59 11:00-19:00 FOH
p01 11:00-18:00 FOH
p14 11:00-16:00 HOST
p08 13:00-17:00 FOH
p35 14:30-18:00 FOH
p04 16:00-22:45 FOH
p14 16:00-18:00 FOH
p26 16:00-22:45 FOH
p19 16:30-20:30 FOH
p60 17:00-22:45 FOH
p48 17:00-22:00 HOST
p03 17:00-21:30 FOH
p44 18:00-22:45 FOH
p09 18:00-22:00 FOH
p38 18:00-22:45 FOH
p28 18:00-22:00 FOH
p50 05:15-06:00 TRUCK
p06 05:15-06:00 TRUCK
p44 16:30-18:00 TRUCK
p63 10:00-14:30 TRAINER
p02 10:00-14:30 TRAINEE
''',
  // Friday
  '''
p61 05:15-06:00 BOH
p58 05:15-11:00 BOH
p47 06:00-16:00 BOH
p50 06:00-15:00 BOH
p43 06:00-15:00 BOH
p06 06:00-14:00 BOH
p05 06:00-14:30 BOH
p22 07:00-14:00 BOH
p66 09:00-10:00 BOH
p61 09:00-10:30 BOH
p62 10:00-22:45 BOH
p61 11:30-15:00 BOH
p16 14:00-20:00 BOH
p49 15:00-22:45 BOH
p20 15:00-22:45 BOH
p33 15:00-22:45 BOH
p24 15:00-22:45 BOH
p40 16:00-22:45 BOH
p32 05:15-14:00 FOH
p29 05:15-10:00 FOH
p57 05:45-10:00 FOH
p45 06:00-13:30 FOH
p07 07:00-14:00 FOH
p02 07:00-15:00 FOH
p42 08:00-10:00 FOH
p42 10:00-14:00 HOST
p35 10:00-16:00 FOH
p63 10:00-15:30 FOH
p15 10:00-17:00 FOH
p01 11:00-18:00 FOH
house-f 11:00-15:00 FOH
p14 11:30-19:30 FOH
house-f 12:00-16:00 FOH
p38 12:00-18:00 FOH
p57 15:00-16:00 FOH
p60 15:00-22:45 FOH
p36 16:00-22:00 FOH
p26 16:00-19:00 FOH
p21 16:00-20:00 FOH
p03 16:30-21:30 FOH
p48 17:00-22:00 HOST
p28 17:00-22:00 FOH
p37 17:00-22:00 FOH
p27 18:00-22:45 FOH
p18 18:00-22:45 FOH
p17 18:00-22:45 FOH
p50 05:15-06:00 TRUCK
p06 05:15-06:00 TRUCK
p61 06:00-09:00 ADMIN
p44 10:00-14:30 ADMIN
p57 10:00-15:00 ADMIN
p29 10:00-14:30 ADMIN
p61 10:30-11:30 ADMIN
p60 14:00-15:00 ADMIN
p44 14:30-16:00 TRUCK
''',
  // Saturday
  '''
p05 05:15-15:00 BOH
p61 05:15-14:30 BOH
p47 06:00-15:00 BOH
p50 06:00-15:00 BOH
house-k 06:00-11:00 ADMIN
p43 06:00-14:00 BOH
p06 06:00-13:00 BOH
p22 07:00-16:00 BOH
p66 09:00-11:00 BOH
p16 10:00-15:00 BOH
house-k 11:00-14:00 ADMIN
p58 14:00-23:00 BOH
p49 15:00-22:45 BOH
p20 15:00-20:00 BOH
p33 15:00-22:45 BOH
p24 15:00-22:45 BOH
p40 15:00-22:45 BOH
p31 16:00-22:45 BOH
house-k 17:00-22:45 ADMIN
p32 05:15-10:00 FOH
p63 05:15-15:00 FOH
p39 06:00-14:00 FOH
p29 06:00-13:00 FOH
p21 06:00-13:00 FOH
p36 07:00-15:00 FOH
p02 07:00-14:30 FOH
p42 08:00-15:00 FOH
p46 08:00-17:00 HOST
p14 10:00-14:00 FOH
p41 10:00-16:00 FOH
p10 11:00-16:00 HOST
p01 11:00-18:00 FOH
p28 11:00-14:00 FOH
p15 11:00-17:00 FOH
p59 14:00-22:45 FOH
p26 14:00-19:00 FOH
p18 15:00-20:00 FOH
p37 15:00-20:00 FOH
p10 16:00-18:00 FOH
p44 17:00-22:45 FOH
p04 17:00-22:00 FOH
p48 17:00-22:00 HOST
p09 17:00-22:00 FOH
p34 18:00-22:45 FOH
p63 18:00-22:45 FOH
p50 05:15-06:00 TRUCK
p06 05:15-06:00 TRUCK
p29 13:00-14:00 TRUCK
p44 15:30-17:00 TRUCK
''',
];

// =============================================================================
// Settings
// =============================================================================

const kitchenBoardId = 'kitchen';
const _leaderTitles = ['Leader', 'Director'];

// Ranked: with N people on, the top N positions are filled.
const _frontPositions = [
  ShiftPosition(id: 'pos_dt_order', name: 'DT Order Taker'),
  ShiftPosition(id: 'pos_front_counter', name: 'Front Counter'),
  ShiftPosition(id: 'pos_dt_window', name: 'DT Window'),
  ShiftPosition(id: 'pos_dt_bagging', name: 'DT Bagging'),
  ShiftPosition(id: 'pos_dt_order_2', name: 'DT Order Taker 2'),
  ShiftPosition(id: 'pos_fc_bagging', name: 'FC Bagging'),
  ShiftPosition(id: 'pos_beverages', name: 'Beverages'),
  ShiftPosition(id: 'pos_front_counter_2', name: 'Front Counter 2'),
  ShiftPosition(id: 'pos_dt_bagging_2', name: 'DT Bagging 2'),
  ShiftPosition(id: 'pos_dt_runner', name: 'DT Runner'),
  ShiftPosition(id: 'pos_dining_room', name: 'Dining Room'),
  ShiftPosition(id: 'pos_dt_runner_2', name: 'DT Runner 2'),
];

const _kitchenPositions = [
  ShiftPosition(id: 'pos_breading', name: 'Breading'),
  ShiftPosition(id: 'pos_machines', name: 'Machines'),
  ShiftPosition(id: 'pos_fries', name: 'Fries'),
  ShiftPosition(id: 'pos_primary', name: 'Primary'),
  ShiftPosition(id: 'pos_breading_2', name: 'Breading 2'),
  ShiftPosition(id: 'pos_secondary', name: 'Secondary'),
  ShiftPosition(id: 'pos_prep', name: 'Prep'),
  ShiftPosition(id: 'pos_dishes', name: 'Dishes'),
  ShiftPosition(id: 'pos_prep_2', name: 'Prep 2'),
];

const _checklistId = 'chk_in_training';
const _checklistItems = [
  'Orientation & food safety',
  'Front Counter',
  'Drive-thru order taking',
  'Drive-thru window & payment',
  'Bagging & expo',
  'Beverages & desserts',
  'Dining room & hospitality',
  'Opening & closing duties',
  'Final sign-off',
];

const _titles = [
  TitleConfig(
    id: 'title_in_training',
    name: _it,
    color: 'Orange',
    linkChecklist: true,
    linkedChecklistId: _checklistId,
  ),
  TitleConfig(id: 'title_team_member', name: _tm, color: 'Red'),
  TitleConfig(id: 'title_seasonal', name: 'Seasonal', color: 'Green'),
  TitleConfig(id: 'title_champion', name: 'Champion', color: 'Teal'),
  TitleConfig(
    id: 'title_leader',
    name: 'Leader',
    color: 'Blue',
    isLeadership: true,
    mgrPermit: true,
  ),
  TitleConfig(
    id: 'title_director',
    name: 'Director',
    color: 'Purple',
    isLeadership: true,
    mgrPermit: true,
  ),
];

const _tags = [
  TitleConfig(id: 'tag_trainer', name: 'Trainer', color: 'Teal'),
  TitleConfig(id: 'tag_truck', name: 'Truck', color: 'Yellow'),
  TitleConfig(id: 'tag_driver', name: 'Driver', color: 'Pink'),
];

// =============================================================================
// Building the week
// =============================================================================

/// What kind of template bar a block needs.
enum _Bar { lead, front, kitchen, host, prep, truck, admin }

class _Block {
  final String who;
  final int start;
  final int end;
  final String kind;
  const _Block(this.who, this.start, this.end, this.kind);
}

int _minutes(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

List<_Block> _parseDay(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty)
      () {
        final parts = line.trim().split(RegExp(r'\s+'));
        final times = parts[1].split('-');
        return _Block(
          parts[0],
          _minutes(times[0]),
          _minutes(times[1]),
          parts[2],
        );
      }(),
];

/// One day of one schedule, built from the sample blocks: the template rows
/// and (for the sample week) everyone's shifts in them.
class _BuiltDay {
  final List<ScheduleRow> rows;
  final List<Shift> shifts;
  const _BuiltDay(this.rows, this.shifts);
}

class SampleSeeder {
  SampleSeeder(this.storeId, {DateTime? today, math.Random? random})
    : today = dateOnly(today ?? DateTime.now()),
      _random = random ?? math.Random();

  final String storeId;
  final DateTime today;
  final math.Random _random;

  /// This seeding's name for each person (by key): a different first and
  /// last name for everyone; now and then the short name they go by.
  late final Map<String, ({String first, String last, String? preferred})>
  _names = () {
    final firsts = [..._firstNames]..shuffle(_random);
    final lasts = [..._lastNames]..shuffle(_random);
    return {
      for (var i = 0; i < _people.length; i++)
        _people[i].id: (
          first: firsts[i].$1,
          last: lasts[i],
          preferred: firsts[i].$2 != null && _random.nextBool()
              ? firsts[i].$2
              : null,
        ),
    };
  }();
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  late final Map<String, _Person> _byId = {for (final p in _people) p.id: p};
  late final List<List<_Block>> _week = _sampleWeek.map(_parseDay).toList();

  /// A team member's id: per store, so two seeded stores don't share ids
  /// (the All Stores lists would merge them into one person).
  String memberId(String key) => 'seed_${storeId}_$key';

  /// A fake login's id: per store, so seeding several stores doesn't make
  /// them share (and steal) each other's logins.
  String loginId(String key) => 'seed_login_${storeId}_$key';

  DocumentReference<Map<String, dynamic>> get _store =>
      _db.collection('stores').doc(storeId);

  bool _isKitchenPerson(String who) {
    if (who == 'house-k') return true;
    if (who == 'house-f') return false;
    final area = _byId[who]?.area;
    return area == 'KT' || area == 'DIR';
  }

  /// Which schedule a block belongs to.
  String _boardOf(_Block b) => switch (b.kind) {
    'BOH' || 'PREP' => kitchenBoardId,
    'FOH' || 'HOST' || 'TRAINER' || 'TRAINEE' => kMainBoardId,
    _ => _isKitchenPerson(b.who) ? kitchenBoardId : kMainBoardId,
  };

  _Bar _barOf(_Block b) {
    final isLeader = _leaderTitles.contains(_byId[b.who]?.title);
    return switch (b.kind) {
      'BOH' => isLeader ? _Bar.lead : _Bar.kitchen,
      'FOH' || 'TRAINER' => isLeader ? _Bar.lead : _Bar.front,
      'HOST' => _Bar.host,
      'TRUCK' => _Bar.truck,
      'ADMIN' => _Bar.admin,
      'PREP' => _Bar.prep,
      _ => _Bar.front,
    };
  }

  ScheduleRow _rowFor(_Bar bar, String board, int n) {
    final id = 'r${n + 1}';
    return switch (bar) {
      _Bar.lead => ScheduleRow(id: id, allowedTitles: _leaderTitles),
      _Bar.host => ScheduleRow(id: id, label: 'Dining Room Host'),
      _Bar.truck =>
        board == kMainBoardId
            ? ScheduleRow(
                id: id,
                label: 'Truck',
                allowedTitles: const ['Truck'],
              )
            : ScheduleRow(id: id, label: 'Truck'),
      _Bar.admin => ScheduleRow(id: id, label: 'Admin'),
      _Bar.prep => ScheduleRow(id: id, label: 'Prep'),
      _Bar.front || _Bar.kitchen => ScheduleRow(id: id),
    };
  }

  /// Packs the blocks of one day + schedule into rows (bars that fit one
  /// after another share a row) and turns each person's blocks into a
  /// shift. Training pairs become one shift with a trainee.
  _BuiltDay _build(List<_Block> all, String board) {
    final blocks = all.where((b) => _boardOf(b) == board).toList();
    final trainees = blocks.where((b) => b.kind == 'TRAINEE').toList();
    // Admin time is off the floor: on the person's shift, not a template bar.
    final adminBlocks = blocks
        .where((b) => b.kind == 'ADMIN' && !b.who.startsWith('house'))
        .toList();
    final working = blocks
        .where((b) => b.kind != 'TRAINEE' && b.kind != 'ADMIN')
        .toList();

    // A person's back-to-back blocks of the same bar kind are one bar.
    final bars =
        <({String who, int start, int end, _Bar bar, bool training})>[];
    final byPerson = <String, List<_Block>>{};
    for (final b in working) {
      (byPerson[b.who] ??= []).add(b);
    }
    for (final entry in byPerson.entries) {
      final list = entry.value..sort((a, b) => a.start.compareTo(b.start));
      for (final b in list) {
        final kind = _barOf(b);
        final last = bars.lastOrNull;
        if (last != null &&
            last.who == b.who &&
            last.bar == kind &&
            last.end == b.start &&
            !entry.key.startsWith('house')) {
          bars[bars.length - 1] = (
            who: last.who,
            start: last.start,
            end: b.end,
            bar: kind,
            training: last.training || b.kind == 'TRAINER',
          );
        } else {
          bars.add((
            who: b.who,
            start: b.start,
            end: b.end,
            bar: kind,
            training: b.kind == 'TRAINER',
          ));
        }
      }
    }

    // Rows: kinds in display order; within a kind, each bar goes after the
    // row that frees up latest before it starts (tight open → close pairs).
    final rowsByKind = <_Bar, List<List<int>>>{}; // bar indexes per row
    final order = [...List.generate(bars.length, (i) => i)]
      ..sort((a, b) {
        final c = bars[a].start.compareTo(bars[b].start);
        return c != 0 ? c : bars[b].end.compareTo(bars[a].end);
      });
    for (final i in order) {
      final bar = bars[i];
      final rows = rowsByKind[bar.bar] ??= [];
      List<int>? best;
      for (final r in rows) {
        final end = bars[r.last].end;
        if (end <= bar.start && (best == null || end > bars[best.last].end)) {
          best = r;
        }
      }
      if (best == null) {
        rows.add([i]);
      } else {
        best.add(i);
      }
    }

    final rows = <ScheduleRow>[];
    final rowOfBar = <int, String>{};
    for (final kind in _Bar.values) {
      for (final r in rowsByKind[kind] ?? const <List<int>>[]) {
        final row = _rowFor(kind, board, rows.length).copyWith(
          windows: mergeWindows(
            r.map((i) => TimeWindow(bars[i].start, bars[i].end)),
          ),
        );
        rows.add(row);
        for (final i in r) {
          rowOfBar[i] = row.id;
        }
      }
    }

    // Shifts: one per person, a piece per bar.
    final shifts = <Shift>[];
    final people = {
      ...bars.map((b) => b.who).where((w) => !w.startsWith('house')),
      ...adminBlocks.map((b) => b.who),
    };
    for (final who in people) {
      final pieces = <ShiftPiece>[
        for (var i = 0; i < bars.length; i++)
          if (bars[i].who == who)
            ShiftPiece(
              id: newScheduleId(),
              rowId: rowOfBar[i]!,
              start: bars[i].start,
              end: bars[i].end,
            ),
        for (final a in adminBlocks)
          if (a.who == who)
            ShiftPiece(
              id: newScheduleId(),
              rowId: kAdminRowId,
              start: a.start,
              end: a.end,
              admin: true,
            ),
      ]..sort((a, b) => a.start.compareTo(b.start));
      // Their trainee: someone training at exactly their TRAINER times.
      String? trainee;
      for (final t in trainees) {
        final paired = working.any(
          (b) =>
              b.who == who &&
              b.kind == 'TRAINER' &&
              b.start == t.start &&
              b.end == t.end,
        );
        if (paired) trainee = memberId(t.who);
      }
      shifts.add(
        Shift(
          id: newScheduleId(),
          userId: memberId(who),
          traineeId: trainee,
          pieces: pieces,
        ),
      );
    }
    return _BuiltDay(rows, shifts);
  }

  /// For tests: sample weekday [d] (0 = Monday) of [board], built.
  @visibleForTesting
  ScheduleDay buildDay(int d, String board) {
    final built = _build(_week[d], board);
    return ScheduleDay(date: 'd$d', rows: built.rows, shifts: built.shifts);
  }

  /// For tests: everyone's member doc, by member id.
  @visibleForTesting
  Map<String, Map<String, dynamic>> memberDocs() => {
    for (final p in _people) memberId(p.id): _memberDoc(p),
  };

  /// For tests: every person key used in the sample week.
  @visibleForTesting
  Set<String> get weekPeople => {
    for (final day in _week) ...day.map((b) => b.who),
  };

  // ---------------------------------------------------------------------------
  // People
  // ---------------------------------------------------------------------------

  /// Days each person is on the sample week (both schedules).
  late final Map<String, int> _daysWorked = () {
    final out = <String, int>{};
    for (final day in _week) {
      for (final who in day.map((b) => b.who).toSet()) {
        out[who] = (out[who] ?? 0) + 1;
      }
    }
    return out;
  }();

  /// Each person's working span on each sample weekday (0 = Monday).
  late final Map<String, Map<int, TimeWindow>> _worked = () {
    final out = <String, Map<int, TimeWindow>>{};
    for (var d = 0; d < _week.length; d++) {
      for (final b in _week[d]) {
        final days = out[b.who] ??= {};
        final w = days[d];
        days[d] = w == null
            ? TimeWindow(b.start, b.end)
            : TimeWindow(
                b.start < w.start ? b.start : w.start,
                b.end > w.end ? b.end : w.end,
              );
      }
    }
    return out;
  }();

  static int _hash(String s) =>
      s.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7fffffff);

  static String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// Made-up availability that fits who they are (school, daytime / night)
  /// and always covers the shifts they have in the sample week.
  Map<String, List<Map<String, String>>> _availability(_Person p) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final h = _hash(p.id);
    final out = <String, List<Map<String, String>>>{};
    if (p.title == 'Seasonal') {
      return {for (final d in days) d: const []}; // away at school
    }
    final worked = _worked[p.id] ?? const <int, TimeWindow>{};

    // Usual windows for a weekday (0 = Monday … 5 = Saturday).
    List<TimeWindow> usual(int d) {
      final leader = _leaderTitles.contains(p.title);
      if (p.title == 'Director') {
        return d < 5 ? const [TimeWindow(8 * 60, 17 * 60)] : const [];
      }
      if (leader) return const [TimeWindow(5 * 60, 23 * 60)];
      switch (p.designation) {
        case 'High School':
          if (d == 5) return const [TimeWindow(7 * 60, 23 * 60)];
          final from = const [16 * 60, 16 * 60 + 30, 17 * 60][h % 3];
          return [TimeWindow(from, 23 * 60)];
        case 'College':
          final tueThu = d == 1 || d == 3;
          if (p.time == 'Night') {
            return d == 5
                ? const [TimeWindow(8 * 60, 23 * 60)]
                : [TimeWindow(tueThu ? 16 * 60 : 14 * 60, 23 * 60)];
          }
          // Daytime college: classes in the middle of Tue/Thu.
          return tueThu
              ? const [
                  TimeWindow(5 * 60, 10 * 60),
                  TimeWindow(15 * 60 + 30, 23 * 60),
                ]
              : const [TimeWindow(5 * 60, 16 * 60)];
        default: // Adult
          return p.time == 'Night'
              ? const [TimeWindow(13 * 60, 23 * 60)]
              : const [TimeWindow(5 * 60, 16 * 60 + 30)];
      }
    }

    // One or two days off a week (never a day they work in the sample week).
    final offDays = <int>{};
    if (!_leaderTitles.contains(p.title)) {
      final free = [
        for (var d = 0; d < 6; d++)
          if (!worked.containsKey(d)) d,
      ];
      final want = p.designation == 'High School' ? 2 : 1;
      for (var k = 0; k < want && free.isNotEmpty; k++) {
        offDays.add(free.removeAt((h >> (k * 3)) % free.length));
      }
    }

    for (var d = 0; d < 7; d++) {
      if (d == 6 || offDays.contains(d)) {
        out[days[d]] = const [];
        continue;
      }
      final windows = [...usual(d)];
      final w = worked[d];
      if (w != null) {
        // Stretch the window they work in (or add one) to cover the shift.
        final i = windows.indexWhere((x) => x.overlaps(w.start, w.end));
        if (i < 0) {
          windows.add(w);
        } else {
          final x = windows[i];
          windows[i] = TimeWindow(
            w.start < x.start ? w.start : x.start,
            w.end > x.end ? w.end : x.end,
          );
        }
      }
      out[days[d]] = [
        for (final x in mergeWindows(windows))
          {'start': _hhmm(x.start), 'end': _hhmm(x.end)},
      ];
    }
    return out;
  }

  double _payRate(_Person p) {
    final h = _hash(p.id) % 4;
    return switch (p.title) {
      'Director' => 26.0 + h,
      'Leader' => 19.5 + h * 0.75,
      'Champion' => 18.0 + h * 0.5,
      _ => switch (p.designation) {
        'High School' => 15.0 + h * 0.5,
        'College' => 16.0 + h * 0.5,
        _ => 16.5 + h * 0.75,
      },
    };
  }

  String _email(_Person p) {
    String clean(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    final n = _names[p.id]!;
    final first = clean(n.preferred ?? n.first);
    final last = clean(n.last);
    return '$first.$last@example.com';
  }

  DateTime _startDate(_Person p) => p.startedDaysAgo != null
      ? addDays(today, -p.startedDaysAgo!)
      : DateTime.parse(p.start);

  Map<String, dynamic> _memberDoc(_Person p) {
    final worked = _daysWorked[p.id] ?? 0;
    final avg = worked > 0
        ? worked
        : switch (p.designation) {
            'High School' => 3,
            'College' => 4,
            _ => 5,
          };
    final user = UserModel(
      firstName: _names[p.id]!.first,
      lastName: _names[p.id]!.last,
      preferredName: _names[p.id]!.preferred,
      email: _email(p),
      title: p.title,
      startDate: _startDate(p),
      endDate: p.leaving ? addDays(today, 21) : null,
      store: storeId,
      position: p.area,
      designation: p.designation,
      additionalTags: p.tags,
      workingTime: p.time,
      avgShifts: p.title == 'Seasonal' ? '0' : '$avg',
      payRate: _payRate(p),
      foodHandlersExpiration: p.permit == null
          ? null
          : DateTime.parse(p.permit!),
      managerPermitExpiration: p.mgrPermit == null
          ? null
          : DateTime.parse(p.mgrPermit!),
      status: 'Active',
      completedTasks: p.checklistDone == null
          ? const []
          : _checklistItems.take(p.checklistDone!).toList(),
      completedChecklists: p.checklistComplete
          ? const [_checklistId]
          : const [],
      historyLogs: [
        {
          'timestamp': _startDate(p).toIso8601String(),
          'event': 'Hired as ${p.title == _it ? _it : _tm}',
        },
      ],
      activeAvailability: _availability(p),
    );
    final data = user.toJson()
      ..remove('id')
      ..removeWhere((_, v) => v == null);
    data['seeded'] = true;
    return data;
  }

  // ---------------------------------------------------------------------------
  // Time off (relative to next week, the one left to build)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _timeOff(DateTime nextWeek) {
    String day(int offset) => dateKey(addDays(nextWeek, offset));
    Map<String, dynamic> req(
      String who,
      int from,
      int to,
      String status,
      String reason, {
      String? startTime,
      String? endTime,
    }) => {
      'user_id': memberId(who),
      'start_date': day(from),
      'end_date': day(to),
      'start_time': ?startTime,
      'end_time': ?endTime,
      'status': status,
      'reason': reason,
      'approved_by': status == 'pending' ? null : 'seed',
      'created_at': addDays(nextWeek, from - 10).toIso8601String(),
      'seeded': true,
    };

    return [
      // Approved, next week
      req('p38', 1, 1, 'approved', 'Doctor appointment'),
      req('p26', 4, 5, 'approved', 'Homecoming weekend'),
      req('p33', 2, 2, 'approved', 'Family event'),
      req(
        'p45',
        3,
        3,
        'approved',
        'Dentist appointment',
        startTime: '06:00',
        endTime: '10:00',
      ),
      req(
        'p36',
        0,
        0,
        'approved',
        'Evening lab class',
        startTime: '16:00',
        endTime: '23:00',
      ),
      req('p22', 5, 5, 'approved', 'Son\'s soccer tournament'),
      // Pending, next week
      req('p04', 5, 5, 'pending', 'Homecoming dance'),
      req(
        'p19',
        4,
        4,
        'pending',
        'Football game',
        startTime: '17:00',
        endTime: '23:00',
      ),
      req('p05', 3, 3, 'pending', 'Appointment'),
      req('p35', 2, 3, 'pending', 'College visit'),
      req(
        'p02',
        1,
        1,
        'pending',
        'Car in the shop',
        startTime: '07:00',
        endTime: '11:00',
      ),
      // Denied
      req('p17', 5, 5, 'denied', 'Concert'),
      req('p16', 4, 4, 'denied', 'Trip with friends'),
      // Later on
      req('p52', 7, 11, 'approved', 'Family vacation'),
      req('p62', 17, 19, 'approved', 'Brother\'s wedding'),
      req('p25', 12, 12, 'pending', 'Band competition'),
      req('p60', 14, 14, 'pending', 'Exam'),
      // Already happened
      req('p58', -21, -19, 'approved', 'Vacation'),
      req('p43', -10, -10, 'approved', 'Sick day'),
    ];
  }

  // ---------------------------------------------------------------------------
  // Seeding
  // ---------------------------------------------------------------------------

  Future<String> seed() async {
    final weekStart = weekStartFor(today, DateTime.monday);
    final nextWeek = addDays(weekStart, 7);

    // 1. Settings ----------------------------------------------------------------
    final settingsRef = _store.collection('settings');
    final current = StoreSettingsModel.fromJson(
      (await settingsRef.doc('global_config').get()).data() ?? const {},
    );
    final settings = current.copyWith(
      titles: _titles,
      tags: _tags,
      positions: const ['SVC', 'DT', 'KT', 'DIR'],
      designations: const ['Adult', 'College', 'High School'],
      workingTimes: const ['Daytime', 'Night', 'Unassigned'],
      checklists: [
        for (final c in current.checklists)
          if (c.id != _checklistId) c,
        const ChecklistConfig(
          id: _checklistId,
          name: _it,
          color: 'Orange',
          items: _checklistItems,
        ),
      ],
      isScheduleEnabled: true,
      isShiftBoardEnabled: true,
    );
    await settingsRef.doc('global_config').set(settings.toJson());
    // How people move up (Seasonal isn't a step on the way).
    await saveTitleJourney(
      storeId,
      const TitleJourney(
        nodes: {
          'title_in_training': JourneyCell(0, 0),
          'title_team_member': JourneyCell(1, 0),
          'title_champion': JourneyCell(2, 0),
          'title_leader': JourneyCell(3, 0),
          'title_director': JourneyCell(4, 0),
        },
        links: [
          JourneyLink('title_in_training', 'title_team_member'),
          JourneyLink('title_team_member', 'title_champion'),
          JourneyLink('title_champion', 'title_leader'),
          JourneyLink('title_leader', 'title_director'),
        ],
      ),
    );

    final repo = ScheduleRepository(storeId);
    // A shift board for each schedule, each with its own positions.
    await repo.saveShiftConfig(
      const ShiftConfig(
        scheduleBoards: {
          kMainBoardId: _frontPositions,
          kitchenBoardId: _kitchenPositions,
        },
      ),
    );
    await repo.saveConfig(
      ScheduleConfig(
        weekStart: DateTime.monday,
        trainingFlowEnabled: true,
        trainingDays: const [
          TrainingDay(training: true),
          TrainingDay(training: true),
          TrainingDay(training: false),
        ],
        trainerTags: const ['Trainer', 'Leader', 'Director'],
        boards: [
          ScheduleBoard(
            id: kMainBoardId,
            name: 'Front of House',
            teamAreas: const ['DT', 'SVC'],
          ),
          ScheduleBoard(
            id: kitchenBoardId,
            name: 'Kitchen',
            teamAreas: const ['KT', 'DIR'],
          ),
        ],
      ),
    );

    // 2. People, logins, availability, time off ------------------------------
    var batch = _db.batch();
    var pending = 0;
    Future<void> put(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data,
    ) async {
      batch.set(ref, data);
      if (++pending >= 400) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    for (final p in _people) {
      final id = memberId(p.id);
      final doc = _memberDoc(p);
      await put(_store.collection('users').doc(id), doc);
      await put(
        _store.collection('active_availability').doc(id),
        Map<String, dynamic>.from(doc['active_availability'] as Map),
      );
      // A login linked to the member, like one made with "Create Account".
      await put(_db.collection('users').doc(loginId(p.id)), {
        'first_name': _names[p.id]!.first,
        'last_name': _names[p.id]!.last,
        'email': doc['email'],
        'role': 'team_member',
        'storeId': storeId,
        'userId': id,
        'needs_password_reset': false,
        'seeded': true,
      });
    }
    // Training review as of next week: the three new hires and two people
    // part way through are in training; everyone else isn't.
    for (final p in _people) {
      final partWay = p.id == 'p10' || p.id == 'p09';
      final inTraining = p.startedDaysAgo != null || partWay;
      await put(_store.collection('training_progress').doc(memberId(p.id)), {
        'done': inTraining ? (partWay ? [0, 1] : <int>[]) : [0, 1, 2],
        'not_in_training': !inTraining,
        'as_of': dateKey(nextWeek),
      });
    }
    final timeOff = _timeOff(nextWeek);
    for (final t in timeOff) {
      await put(_store.collection('time_off_requests').doc(), t);
    }
    if (pending > 0) await batch.commit();

    // Shifts needed per day by roster area (Rosters page), from the week.
    final perArea = <String, int>{};
    for (final day in _week) {
      for (final who in day.map((b) => b.who).toSet()) {
        final area = _byId[who]?.area;
        if (area != null) perArea[area] = (perArea[area] ?? 0) + 1;
      }
    }
    await settingsRef.doc('roster_needs').set({
      for (final e in perArea.entries) e.key: (e.value / _week.length).round(),
    });

    // 3. Templates, this week (posted) and next week (to build) --------------
    var templates = 0;
    for (final board in [kMainBoardId, kitchenBoardId]) {
      final boardRepo = ScheduleRepository(storeId, boardId: board);
      final positions = board == kMainBoardId
          ? _frontPositions
          : _kitchenPositions;
      final prefix = board == kMainBoardId ? 'Front of House' : 'Kitchen';
      final thisWeek = <ScheduleDay>[];
      for (var d = 0; d < _week.length; d++) {
        final built = _build(_week[d], board);
        final template = ScheduleTemplate(
          id: 'seed_${board}_${weekdayShort[d].toLowerCase()}',
          name: '$prefix · ${weekdayNames[d]}',
          rows: built.rows,
          storeIds: [storeId],
        );
        await boardRepo.saveTemplate(template);
        templates++;

        final day = ScheduleDay(
          date: dateKey(addDays(weekStart, d)),
          templateId: template.id,
          templateName: template.name,
          rows: built.rows,
          shifts: built.shifts,
        );
        thisWeek.add(deployPositions(day, positions));

        await boardRepo.saveDay(
          ScheduleDay(
            date: dateKey(addDays(nextWeek, d)),
            templateId: template.id,
            templateName: template.name,
            rows: built.rows,
          ),
        );
      }
      await boardRepo.postWeek(weekStart, thisWeek, postedBy: 'seed');
    }

    final weekLabel = '${monthShort[nextWeek.month - 1]} ${nextWeek.day}';
    return 'Added ${_people.length} team members with logins, '
        '${timeOff.length} time off requests and $templates templates. '
        'This week is filled in and posted; the week of $weekLabel is ready '
        'to build.';
  }
}
