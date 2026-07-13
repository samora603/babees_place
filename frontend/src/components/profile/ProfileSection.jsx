/**
 * Reusable profile page section shell.
 */
export default function ProfileSection({ title, description, children, id }) {
  return (
    <section id={id} className="card p-6 space-y-4" aria-labelledby={id ? `${id}-heading` : undefined}>
      <div>
        <h2 id={id ? `${id}-heading` : undefined} className="font-display font-semibold text-xl text-white">
          {title}
        </h2>
        {description && <p className="text-sm text-slate-400 mt-1">{description}</p>}
      </div>
      {children}
    </section>
  );
}
