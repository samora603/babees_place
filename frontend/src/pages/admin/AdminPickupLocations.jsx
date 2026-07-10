import { useEffect, useState } from 'react';
import { adminService } from '@/services/adminService';
import Modal from '@/components/ui/Modal';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';
import { FiPlus, FiEdit2, FiMapPin, FiClock } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';

const blank = { name: '', building: '', description: '', operatingHours: { weekdays: { open: '08:00', close: '18:00' }, weekends: { open: '09:00', close: '15:00' } } };

export default function AdminPickupLocations() {
  const [locations, setLocations] = useState([]);
  const [modal, setModal] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(blank);
  const [saving, setSaving] = useState(false);

  const fetchLocations = () => adminService.getPickupLocations().then(({ data }) => setLocations(data.data));
  useEffect(() => { fetchLocations(); }, []);

  const openNew = () => { setEditing(null); setForm(blank); setModal(true); };
  const openEdit = (loc) => { setEditing(loc); setForm({ name: loc.name, building: loc.building, description: loc.description || '', operatingHours: loc.operatingHours || blank.operatingHours }); setModal(true); };

  const handleSave = async () => {
    setSaving(true);
    try {
      if (editing) await adminService.updatePickupLocation(editing._id, form);
      else await adminService.addPickupLocation(form);
      toast.success(editing ? 'Boutique details updated' : 'Boutique location added');
      setModal(false);
      fetchLocations();
    } catch { toast.error('Command failed'); }
    finally { setSaving(false); }
  };

  return (
    <div className="space-y-8 bg-[#0B0B0B] min-h-full pb-12">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-brand-500/10 pb-6 relative">
        <div className="absolute top-0 right-0 w-40 h-40 bg-brand-500/5 rounded-full blur-[60px] pointer-events-none"></div>
        <div>
          <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase flex items-center gap-3">
             <GiBee className="text-brand-500/80" /> Boutique Network
          </h1>
          <p className="text-sm text-slate-400 font-light mt-1">Manage physical pickup hubs</p>
        </div>
        <button onClick={openNew} id="add-pickup-btn" className="btn-primary flex items-center gap-2 text-sm uppercase tracking-widest px-6 py-3 shadow-[0_0_15px_rgba(212,175,55,0.2)] hover:shadow-[0_0_20px_rgba(212,175,55,0.4)]">
          <FiPlus /> Establish Hub
        </button>
      </div>

      <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-6 relative z-10">
        {locations.map((loc) => (
          <div key={loc._id} className="bg-[#111] p-6 rounded-2xl border border-brand-500/10 shadow-[0_10px_30px_rgba(0,0,0,0.5)] flex flex-col justify-between group hover:border-brand-500/30 transition-all duration-300 relative overflow-hidden">
            <div className="absolute -right-4 -top-4 w-24 h-24 bg-brand-500/5 rounded-full blur-[20px] pointer-events-none group-hover:bg-brand-500/10 transition-colors"></div>
            
            <div>
              <div className="flex justify-between items-start mb-4">
                 <div className="w-10 h-10 rounded-xl bg-[#0A0A0A] border border-brand-500/20 flex items-center justify-center text-brand-500 group-hover:scale-110 transition-transform">
                    <FiMapPin size={18} />
                 </div>
                 <button onClick={() => openEdit(loc)} className="w-8 h-8 rounded border border-transparent hover:border-brand-500/30 bg-surface-card hover:bg-[#0A0A0A] flex items-center justify-center text-slate-400 hover:text-white transition-all shadow-sm">
                    <FiEdit2 size={14} />
                 </button>
              </div>
              <h3 className="font-display font-bold text-lg text-white tracking-wide mb-1 group-hover:text-brand-400 transition-colors">{loc.name}</h3>
              <p className="text-sm text-slate-400 font-medium mb-3">{loc.building}</p>
              {loc.description && <p className="text-[11px] text-slate-500 leading-relaxed mb-4">{loc.description}</p>}
            </div>
            
            <div className="pt-4 border-t border-brand-500/10 mt-auto">
               <div className="flex items-center gap-2 text-[10px] uppercase tracking-widest text-brand-500/80 font-semibold mb-2">
                  <FiClock /> Operating Hours
               </div>
               <div className="grid grid-cols-2 gap-2 text-xs text-slate-400 font-mono">
                  <div>
                    <span className="text-slate-500 block text-[9px] uppercase">Weekdays</span>
                    {loc.operatingHours?.weekdays?.open} – {loc.operatingHours?.weekdays?.close}
                  </div>
                  <div>
                    <span className="text-slate-500 block text-[9px] uppercase">Weekends</span>
                    {loc.operatingHours?.weekends?.open} – {loc.operatingHours?.weekends?.close}
                  </div>
               </div>
            </div>
          </div>
        ))}
      </div>

      <Modal isOpen={modal} onClose={() => setModal(false)} title={editing ? 'Modify Hub Protocol' : 'Establish New Hub'}>
        <div className="space-y-5 pt-2">
          <div>
            <label className="text-[11px] font-semibold uppercase tracking-widest text-slate-400 block mb-2">Hub Nomenclature <span className="text-brand-500">*</span></label>
            <input placeholder="e.g. Westlands Premier" required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} className="input bg-[#111] border-brand-500/20 focus:border-brand-500 text-white w-full py-3 shadow-inner" id="pickup-name" />
          </div>
          <div>
            <label className="text-[11px] font-semibold uppercase tracking-widest text-slate-400 block mb-2">Facility Location <span className="text-brand-500">*</span></label>
            <input placeholder="Building/Street Details" required value={form.building} onChange={(e) => setForm({ ...form, building: e.target.value })} className="input bg-[#111] border-brand-500/20 focus:border-brand-500 text-white w-full py-3 shadow-inner" id="pickup-building" />
          </div>
          <div>
            <label className="text-[11px] font-semibold uppercase tracking-widest text-slate-400 block mb-2">Access Instructions (Optional)</label>
            <input placeholder="Specific directions for access..." value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} className="input bg-[#111] border-brand-500/20 focus:border-brand-500 text-white w-full py-3 shadow-inner" id="pickup-desc" />
          </div>
          <div className="pt-4 flex gap-4">
             <Button onClick={handleSave} loading={saving} className="flex-1 shadow-[0_4px_20px_rgba(212,175,55,0.2)]">Execute Changes</Button>
             <Button onClick={() => setModal(false)} variant="secondary" className="px-6 bg-[#0A0A0A] border-surface-border text-slate-300">Abort</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
