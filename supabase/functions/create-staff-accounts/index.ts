import {staffMaintenance} from '../_shared/staff_maintenance.mjs';
import {staffServices} from '../_shared/staff_adapter.ts';
Deno.serve((request: Request)=>staffMaintenance(request,staffServices(),'provision'));
