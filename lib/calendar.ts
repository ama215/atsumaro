export const shiftMonth = (month: string, offset: number) => {
  const [year, monthNumber] = month.split("-").map(Number);
  const totalMonths = year * 12 + monthNumber - 1 + offset;
  const nextYear = Math.floor(totalMonths / 12);
  const nextMonth = totalMonths - nextYear * 12 + 1;
  return `${String(nextYear).padStart(4, "0")}-${String(nextMonth).padStart(2, "0")}`;
};

export const dateRange = (start: string, end: string) => {
  const out: string[] = [];
  const d = new Date(`${start}T00:00:00`);
  const last = new Date(`${end}T00:00:00`);
  while (d <= last && out.length < 125) {
    // Keep calendar dates in local time; UTC conversion can change the day.
    out.push(`${String(d.getFullYear()).padStart(4, "0")}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`);
    d.setDate(d.getDate() + 1);
  }
  return out;
};
