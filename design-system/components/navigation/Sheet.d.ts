export interface SheetProps {
  title?: string;
  /** usually Cancel */
  leading?: ReactNode;
  /** usually the confirming action */
  trailing?: ReactNode;
  style?: React.CSSProperties;
}
export declare function Sheet(props: SheetProps): JSX.Element;
